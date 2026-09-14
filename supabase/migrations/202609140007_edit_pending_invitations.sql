begin;

create function public.update_invitation(
  p_invitation_id uuid,
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
  v_invite public.invitations;
  v_token text;
begin
  select * into v_invite
  from public.invitations
  where id = p_invitation_id
  for update;

  if v_invite.id is null
     or v_invite.status <> 'pending'
     or not public.is_chitti_admin(v_invite.chitti_id) then
    raise exception 'Pending invitation not found';
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
    where cm.chitti_id = v_invite.chitti_id
      and lower(p.email) = lower(btrim(p_email))
  ) or exists(
    select 1
    from public.invitations i
    where i.chitti_id = v_invite.chitti_id
      and i.id <> p_invitation_id
      and lower(i.invited_email) = lower(btrim(p_email))
  ) then
    raise exception 'This email is already associated with this chitti';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  delete from public.notifications
  where dedupe_key = 'invite:' || p_invitation_id
    and user_id in (
      select id
      from public.profiles
      where lower(email) = lower(v_invite.invited_email)
    );

  update public.invitations
  set invited_name = btrim(p_name),
      invited_email = lower(btrim(p_email)),
      invited_phone = btrim(p_phone),
      token_hash = extensions.digest(v_token, 'sha256'),
      expires_at = now() + interval '30 days'
  where id = p_invitation_id;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select
    id,
    'invitation.created',
    'You have a private Chitti invitation',
    'Open Chitti to review your invitation.',
    '/invite?invitation=' || p_invitation_id,
    'invite:' || p_invitation_id
  from public.profiles
  where lower(email) = lower(btrim(p_email))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(),
    v_invite.chitti_id,
    'invitation.updated',
    'invitation',
    p_invitation_id::text,
    jsonb_build_object(
      'previous_email', v_invite.invited_email,
      'new_email', lower(btrim(p_email)),
      'link_rotated', true
    )
  );

  return jsonb_build_object(
    'invitation_id', p_invitation_id,
    'token', v_token
  );
end;
$$;

revoke all on function public.update_invitation(uuid, text, text, text) from public, anon;
grant execute on function public.update_invitation(uuid, text, text, text) to authenticated;

commit;
