begin;

-- Only live invitations reserve a month; cancelled/expired records remain auditable.
drop index public.invitations_chitti_payout_position_idx;
create unique index invitations_chitti_payout_position_idx
  on public.invitations(chitti_id, payout_position)
  where payout_position is not null and status in ('pending', 'accepted');

create or replace function public.add_imported_chitti_invitation(
  p_chitti_id uuid,
  p_name text,
  p_email text,
  p_phone text,
  p_payout_position smallint
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
  v_extending boolean;
begin
  -- Serialize adding a month with other invitations, ranking edits and activation.
  select * into v_chitti from public.chittis where id = p_chitti_id for update;
  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if not v_chitti.is_imported or v_chitti.status <> 'inviting'
     or v_chitti.locked_at is not null
     or exists(select 1 from public.rounds where chitti_id = p_chitti_id) then
    raise exception 'Payout-month invitations can only be added while an imported chitti is pending';
  end if;
  if p_payout_position is null or p_payout_position < 2
     or p_payout_position > v_chitti.member_count + 1 or p_payout_position > 50 then
    raise exception 'Choose an empty payout month or the next month, up to 50';
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 80 then
    raise exception 'Enter a valid member name';
  end if;
  if p_email is null or position('@' in btrim(p_email)) < 2 then
    raise exception 'Enter a valid email address';
  end if;
  if p_phone is null or char_length(btrim(p_phone)) < 8 then
    raise exception 'Enter a valid phone number';
  end if;
  if exists(
    select 1 from public.chitti_members member
    join public.profiles profile on profile.id = member.user_id
    where member.chitti_id = p_chitti_id
      and (lower(profile.email) = lower(btrim(p_email)) or member.payout_position = p_payout_position)
  ) or exists(
    select 1 from public.invitations invitation
    where invitation.chitti_id = p_chitti_id and invitation.status in ('pending', 'accepted')
      and (lower(invitation.invited_email) = lower(btrim(p_email)) or invitation.payout_position = p_payout_position)
  ) then
    raise exception 'This email or payout month is already assigned';
  end if;

  v_extending := p_payout_position = v_chitti.member_count + 1;
  if v_extending then
    if exists(
      select 1 from generate_series(2, v_chitti.member_count) slot(position)
      where not exists(
        select 1 from public.chitti_members member
        where member.chitti_id = p_chitti_id and member.payout_position = slot.position
      ) and not exists(
        select 1 from public.invitations invitation
        where invitation.chitti_id = p_chitti_id and invitation.status in ('pending', 'accepted')
          and invitation.payout_position = slot.position
      )
    ) then
      raise exception 'Fill the empty payout months before adding another month';
    end if;

    -- The schedule trigger also extends end_date. Existing positions and history are untouched.
    update public.chittis set member_count = p_payout_position where id = p_chitti_id;
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.invitations(
    chitti_id, invited_name, invited_email, invited_phone, token_hash, payout_position
  ) values (
    p_chitti_id, btrim(p_name), lower(btrim(p_email)), btrim(p_phone),
    extensions.digest(v_token, 'sha256'), p_payout_position
  ) returning id into v_invitation_id;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select id, 'invitation.created', 'You have an existing Chitti invitation',
    'Open Chitti to join payout month ' || p_payout_position || '.',
    '/invite?invitation=' || v_invitation_id, 'invite:' || v_invitation_id
  from public.profiles where lower(email) = lower(btrim(p_email))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(), p_chitti_id, 'invitation.imported_position_added', 'invitation',
    v_invitation_id::text, jsonb_build_object(
      'payout_position', p_payout_position,
      'previous_member_count', v_chitti.member_count,
      'member_count', greatest(v_chitti.member_count, p_payout_position),
      'schedule_extended', v_extending
    )
  );
  if v_extending then
    perform public.notify_chitti_members(
      p_chitti_id, 'chitti.schedule_extended', 'Existing chitti extended',
      v_chitti.name || ' now has ' || p_payout_position || ' payout months. Your payout position is unchanged.',
      '/chitti/' || p_chitti_id, v_invitation_id::text, null
    );
  end if;

  return jsonb_build_object(
    'invitation_id', v_invitation_id, 'token', v_token, 'payout_position', p_payout_position
  );
end;
$$;

revoke all on function public.add_imported_chitti_invitation(uuid, text, text, text, smallint) from public, anon;
grant execute on function public.add_imported_chitti_invitation(uuid, text, text, text, smallint) to authenticated;

commit;
