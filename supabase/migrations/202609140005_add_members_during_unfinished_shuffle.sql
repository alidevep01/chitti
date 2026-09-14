begin;

create or replace function public.add_chitti_member_invitation(
  p_chitti_id uuid,
  p_name text,
  p_email text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_invitation_id uuid;
  v_token text;
  v_late boolean;
  v_shuffle_reset boolean;
begin
  select * into v_chitti
  from public.chittis
  where id = p_chitti_id
  for update;

  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if v_chitti.status not in ('inviting', 'ready', 'shuffle_scheduled', 'awaiting_approval', 'active') then
    raise exception 'Members cannot be added to this chitti';
  end if;
  if v_chitti.member_count >= 50 then
    raise exception 'A chitti can have at most 50 members';
  end if;
  if char_length(btrim(p_name)) not between 2 and 80 then
    raise exception 'Enter a valid member name';
  end if;
  if position('@' in p_email) < 2 then
    raise exception 'Enter a valid email address';
  end if;
  if char_length(btrim(p_phone)) < 8 then
    raise exception 'Enter a valid phone number';
  end if;
  if exists(
    select 1
    from public.chitti_members cm
    join public.profiles p on p.id = cm.user_id
    where cm.chitti_id = p_chitti_id
      and lower(p.email) = lower(btrim(p_email))
  ) or exists(
    select 1
    from public.invitations i
    where i.chitti_id = p_chitti_id
      and lower(i.invited_email) = lower(btrim(p_email))
      and i.status = 'pending'
  ) then
    raise exception 'This email is already a member or has a pending invitation';
  end if;

  v_late := v_chitti.status = 'active';
  v_shuffle_reset := v_chitti.status in ('shuffle_scheduled', 'awaiting_approval');
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.invitations(
    chitti_id,
    invited_name,
    invited_email,
    invited_phone,
    token_hash,
    late_join
  ) values (
    p_chitti_id,
    btrim(p_name),
    lower(btrim(p_email)),
    btrim(p_phone),
    extensions.digest(v_token, 'sha256'),
    v_late
  )
  returning id into v_invitation_id;

  if not v_late then
    if v_shuffle_reset then
      update public.shuffle_runs
      set status = 'rejected'
      where chitti_id = p_chitti_id
        and status in ('pending', 'revealed');

      perform public.notify_chitti_members(
        p_chitti_id,
        'shuffle.reset_for_new_member',
        'A new shuffle will be needed',
        'The administrator added a member before activation. Shuffle again after they join.',
        '/chitti/' || p_chitti_id,
        v_invitation_id::text,
        null
      );
    end if;

    update public.chittis
    set member_count = member_count + 1,
        status = 'inviting',
        shuffle_scheduled_at = null
    where id = p_chitti_id;
  end if;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select
    id,
    'invitation.created',
    'You have a private Chitti invitation',
    'Open Chitti to review your invitation.',
    '/invite?invitation=' || v_invitation_id,
    'invite:' || v_invitation_id
  from public.profiles
  where lower(email) = lower(btrim(p_email))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(),
    p_chitti_id,
    'invitation.added',
    'invitation',
    v_invitation_id::text,
    jsonb_build_object(
      'late_join', v_late,
      'shuffle_reset', v_shuffle_reset,
      'invited_email', lower(btrim(p_email))
    )
  );

  return jsonb_build_object(
    'invitation_id', v_invitation_id,
    'token', v_token,
    'late_join', v_late,
    'shuffle_reset', v_shuffle_reset
  );
end;
$$;

revoke all on function public.add_chitti_member_invitation(uuid, text, text, text) from public, anon;
grant execute on function public.add_chitti_member_invitation(uuid, text, text, text) to authenticated;

commit;
