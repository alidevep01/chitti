begin;

create or replace function public.import_existing_chitti(input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_invite jsonb;
  v_token text;
  v_invitation_id uuid;
  v_links jsonb := '[]'::jsonb;
  v_count int;
  v_completed int;
  v_invite_count int;
  v_position int;
begin
  if not public.is_admin() then
    raise exception 'Only the administrator can import a chitti';
  end if;

  v_count := (input->>'memberCount')::int;
  v_completed := (input->>'completedMonths')::int;
  v_invite_count := coalesce(jsonb_array_length(input->'invites'), 0);
  if v_count not between 2 and 50 then
    raise exception 'Member count must be between 2 and 50';
  end if;
  if v_completed not between 0 and v_count then
    raise exception 'Completed months must be between zero and the member count';
  end if;
  if v_invite_count > v_count - 1 then
    raise exception 'There are more invitations than available payout months';
  end if;
  if (input->>'firstDueDate')::date < (input->>'startDate')::date then
    raise exception 'The first due date cannot be before the start date';
  end if;

  insert into public.chittis(
    name, description, admin_id, monthly_amount_paise, member_count,
    start_date, first_due_date, due_day, upi_id, payee_name, status,
    is_imported, imported_completed_months
  ) values (
    input->>'name', nullif(input->>'description', ''), auth.uid(),
    (input->>'monthlyAmountPaise')::bigint, v_count,
    (input->>'startDate')::date, (input->>'firstDueDate')::date,
    (input->>'dueDay')::smallint, input->>'upiId', input->>'payeeName',
    'inviting', true, v_completed
  ) returning * into v_chitti;

  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position)
  values (v_chitti.id, auth.uid(), true, 1);

  for v_invite in select value from jsonb_array_elements(coalesce(input->'invites', '[]'::jsonb))
  loop
    v_position := (v_invite->>'payoutPosition')::int;
    if v_position not between 2 and v_count then
      raise exception 'Each imported member needs an available payout month between 2 and %', v_count;
    end if;
    if lower(v_invite->>'email') = lower(coalesce(auth.jwt()->>'email', '')) then
      raise exception 'The administrator cannot also be invited as a member';
    end if;

    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.invitations(
      chitti_id, invited_name, invited_email, invited_phone, token_hash, payout_position
    ) values (
      v_chitti.id, btrim(v_invite->>'name'), lower(btrim(v_invite->>'email')),
      btrim(v_invite->>'phone'), extensions.digest(v_token, 'sha256'), v_position
    ) returning id into v_invitation_id;

    v_links := v_links || jsonb_build_array(jsonb_build_object(
      'id', v_invitation_id,
      'name', v_invite->>'name',
      'email', lower(v_invite->>'email'),
      'payoutPosition', v_position,
      'token', v_token
    ));

    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    select id, 'invitation.created', 'You have an existing Chitti invitation',
      'Open Chitti to join the saved payout order.',
      '/invite?invitation=' || v_invitation_id, 'invite:' || v_invitation_id
    from public.profiles
    where lower(email) = lower(v_invite->>'email')
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
  end loop;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(), v_chitti.id, 'chitti.imported', 'chitti', v_chitti.id::text,
    jsonb_build_object(
      'completed_months', v_completed,
      'member_count', v_count,
      'initial_invitations', v_invite_count
    )
  );

  return jsonb_build_object('chitti_id', v_chitti.id, 'invitations', v_links);
end;
$$;

create function public.add_imported_chitti_invitation(
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
begin
  select * into v_chitti
  from public.chittis
  where id = p_chitti_id
  for update;

  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if not v_chitti.is_imported or v_chitti.status <> 'inviting' then
    raise exception 'Payout-month invitations can only be added while an imported chitti is pending';
  end if;
  if p_payout_position not between 2 and v_chitti.member_count then
    raise exception 'Choose an available payout month between 2 and %', v_chitti.member_count;
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
    from public.chitti_members member
    join public.profiles profile on profile.id = member.user_id
    where member.chitti_id = p_chitti_id
      and (
        lower(profile.email) = lower(btrim(p_email))
        or member.payout_position = p_payout_position
      )
  ) or exists(
    select 1
    from public.invitations invitation
    where invitation.chitti_id = p_chitti_id
      and invitation.status in ('pending', 'accepted')
      and (
        lower(invitation.invited_email) = lower(btrim(p_email))
        or invitation.payout_position = p_payout_position
      )
  ) then
    raise exception 'This email or payout month is already assigned';
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
  from public.profiles
  where lower(email) = lower(btrim(p_email))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(), p_chitti_id, 'invitation.imported_position_added', 'invitation',
    v_invitation_id::text, jsonb_build_object('payout_position', p_payout_position)
  );

  return jsonb_build_object(
    'invitation_id', v_invitation_id,
    'token', v_token,
    'payout_position', p_payout_position
  );
end;
$$;

create function public.cancel_chitti(p_chitti_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
begin
  select * into v_chitti
  from public.chittis
  where id = p_chitti_id
  for update;

  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if v_chitti.status not in ('draft', 'inviting', 'ready', 'shuffle_scheduled', 'awaiting_approval') then
    raise exception 'Only a chitti that has not started can be deleted';
  end if;

  delete from public.notifications notification
  where notification.dedupe_key in (
    select 'invite:' || invitation.id
    from public.invitations invitation
    where invitation.chitti_id = p_chitti_id and invitation.status = 'pending'
  );

  update public.invitations
  set status = 'revoked'
  where chitti_id = p_chitti_id and status = 'pending';

  update public.shuffle_runs
  set status = 'rejected'
  where chitti_id = p_chitti_id and status in ('pending', 'revealed');

  update public.chittis
  set status = 'cancelled', archived_at = now()
  where id = p_chitti_id;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select member.user_id, 'chitti.cancelled', 'Chitti cancelled',
    v_chitti.name || ' was cancelled by the administrator.', '/dashboard',
    'cancelled:' || p_chitti_id
  from public.chitti_members member
  where member.chitti_id = p_chitti_id and member.user_id <> auth.uid()
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(), p_chitti_id, 'chitti.cancelled', 'chitti', p_chitti_id::text,
    jsonb_build_object('previous_status', v_chitti.status)
  );
end;
$$;

alter function public.get_app_snapshot() rename to get_app_snapshot_without_incremental_imports;

create function public.get_app_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_snapshot jsonb;
begin
  v_snapshot := public.get_app_snapshot_without_incremental_imports();
  return jsonb_set(
    v_snapshot,
    '{chittis}',
    coalesce((
      select jsonb_agg(
        chitti_item || jsonb_build_object(
          'invitations', coalesce((
            select jsonb_agg(
              invitation_item || jsonb_build_object(
                'payoutPosition', invitation.payout_position
              ) order by invitation_order
            )
            from jsonb_array_elements(chitti_item->'invitations') with ordinality
              as invitation_items(invitation_item, invitation_order)
            join public.invitations invitation
              on invitation.id = (invitation_item->>'id')::uuid
          ), '[]'::jsonb)
        ) order by chitti_order
      )
      from jsonb_array_elements(v_snapshot->'chittis') with ordinality
        as chitti_items(chitti_item, chitti_order)
    ), '[]'::jsonb),
    true
  );
end;
$$;

revoke all on function public.import_existing_chitti(jsonb) from public, anon;
grant execute on function public.import_existing_chitti(jsonb) to authenticated;
revoke all on function public.add_imported_chitti_invitation(uuid, text, text, text, smallint) from public, anon;
grant execute on function public.add_imported_chitti_invitation(uuid, text, text, text, smallint) to authenticated;
revoke all on function public.cancel_chitti(uuid) from public, anon;
grant execute on function public.cancel_chitti(uuid) to authenticated;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

commit;
