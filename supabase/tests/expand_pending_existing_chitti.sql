begin;

do $$
declare
  v_admin constant uuid := 'b9111111-1111-4111-8111-111111111111';
  v_chitti constant uuid := 'b9222222-2222-4222-8222-222222222222';
  v_empty constant uuid := 'b9333333-3333-4333-8333-333333333333';
  v_user uuid;
  v_result jsonb;
  v_order jsonb;
  v_invite uuid;
  v_item record;
  v_position smallint;
  v_status public.chitti_status;
begin
  insert into auth.users(id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (v_admin, 'authenticated', 'authenticated', 'expand-admin@example.com', now(), '{}', '{"full_name":"Expand admin"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = v_admin;
  for i in 2..9 loop
    v_user := ('b9000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    insert into auth.users(id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (v_user, 'authenticated', 'authenticated', 'expand-' || i || '@example.com', now(), '{}', '{"full_name":"Expand member"}', now(), now());
  end loop;
  -- Mirrors the reported seven-slot import: four joined members, three pending invitations.
  insert into public.chittis(id, name, admin_id, monthly_amount_paise, member_count, start_date, first_due_date, due_day, upi_id, payee_name, status, is_imported, imported_completed_months)
  values (v_chitti, 'Seven existing positions', v_admin, 2000000, 7, '2026-01-31', '2026-01-31', 31, 'admin@test', 'Expand admin', 'inviting', true, 3),
    (v_empty, 'Empty positions', v_admin, 2000000, 3, '2026-01-31', '2026-01-31', 31, 'admin@test', 'Expand admin', 'inviting', true, 0);
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position)
  values (v_chitti, v_admin, true, 1), (v_empty, v_admin, true, 1);
  for i in 2..7 loop
    v_user := ('b9000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    if i in (3, 4, 6) then
      insert into public.chitti_members(chitti_id, user_id, payout_position) values (v_chitti, v_user, i);
    else
      insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash, payout_position)
      values (v_chitti, 'Member ' || i, 'expand-' || i || '@example.com', '9000000000', extensions.digest('expand-token-' || i, 'sha256'), i);
    end if;
  end loop;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', 'b9000000-0000-4000-8000-000000000003', 'email', 'expand-3@example.com')::text, true);
  set local role authenticated;
  begin
    perform public.add_imported_chitti_invitation(v_chitti, 'New member', 'expand-8@example.com', '9000000000', 8::smallint);
    raise exception 'TEST: non-admin extension allowed';
  exception when others then
    if sqlerrm <> 'Administrator access required' then raise; end if;
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'expand-admin@example.com')::text, true);
  set local role authenticated;
  -- Failed requests must never increment capacity, including duplicate emails on the new slot.
  begin
    perform public.add_imported_chitti_invitation(v_chitti, 'Duplicate member', 'EXPAND-3@example.com', '9000000000', 8::smallint);
    raise exception 'TEST: duplicate email allowed';
  exception when others then
    if sqlerrm <> 'This email or payout month is already assigned' then raise; end if;
  end;
  foreach v_position in array array[null, 0, 1, 9, 51]::smallint[] loop
    begin
      perform public.add_imported_chitti_invitation(v_chitti, 'Invalid position', 'invalid@example.com', '9000000000', v_position);
      raise exception 'TEST: invalid position allowed';
    exception when others then
      if sqlerrm <> 'Choose an empty payout month or the next month, up to 50' then raise; end if;
    end;
  end loop;
  if (select member_count from public.chittis where id = v_chitti) <> 7 then raise exception 'Failed invitation changed capacity'; end if;

  select public.add_imported_chitti_invitation(v_chitti, 'Eighth member', 'expand-8@example.com', '9000000000', 8::smallint) into v_result;
  v_invite := (v_result->>'invitation_id')::uuid;
  if (v_result->>'payout_position')::int <> 8 or v_result->>'token' is null then raise exception 'Missing invitation result'; end if;
  if not exists(select 1 from public.chittis where id = v_chitti and member_count = 8 and end_date = '2026-08-31' and imported_completed_months = 3 and status = 'inviting' and locked_at is null) then
    raise exception 'Extension did not preserve history and update the end date';
  end if;
  if exists(select 1 from public.rounds where chitti_id = v_chitti) then raise exception 'Import activated before all invitations were accepted'; end if;
  if exists(select 1 from public.chitti_members where chitti_id = v_chitti and payout_position <> case when is_admin then 1 else right(user_id::text, 1)::int end)
     or exists(select 1 from public.invitations where chitti_id = v_chitti and payout_position <> substring(invited_email from 'expand-([0-9]+)')::int) then
    raise exception 'Existing ranking was modified';
  end if;
  -- Stale clients cannot claim the same final month or grow the schedule again accidentally.
  begin
    perform public.add_imported_chitti_invitation(v_chitti, 'Stale client', 'expand-9@example.com', '9000000000', 8::smallint);
    raise exception 'TEST: stale duplicate position allowed';
  exception when others then
    if sqlerrm <> 'This email or payout month is already assigned' then raise; end if;
  end;
  begin
    perform public.add_imported_chitti_invitation(v_empty, 'Skipping slots', 'skip@example.com', '9000000000', 4::smallint);
    raise exception 'TEST: empty positions were skipped';
  exception when others then
    if sqlerrm <> 'Fill the empty payout months before adding another month' then raise; end if;
  end;
  perform public.add_imported_chitti_invitation(v_empty, 'Fill slot', 'fill@example.com', '9000000000', 2::smallint);
  if (select member_count from public.chittis where id = v_empty) <> 3 then raise exception 'Filling a planned slot extended the schedule'; end if;
  execute 'reset role';
  if not exists(select 1 from public.audit_events where chitti_id = v_chitti and detail->>'schedule_extended' = 'true' and detail->>'previous_member_count' = '7' and detail->>'member_count' = '8') then raise exception 'Missing expansion audit'; end if;
  if not exists(select 1 from public.notifications where user_id = 'b9000000-0000-4000-8000-000000000008' and dedupe_key = 'invite:' || v_invite) then raise exception 'Missing invitation notification'; end if;
  if not exists(select 1 from public.notifications where user_id = 'b9000000-0000-4000-8000-000000000003' and kind = 'chitti.schedule_extended') then raise exception 'Joined members were not notified'; end if;

  -- Withdrawn invitations do not permanently occupy their month.
  update public.invitations set status = 'revoked' where chitti_id = v_empty;
  set local role authenticated;
  perform public.add_imported_chitti_invitation(v_empty, 'Replacement', 'replacement@example.com', '9000000000', 2::smallint);
  execute 'reset role';

  -- Enforce cap and lifecycle guard on the server, not just in the UI.
  update public.chittis set member_count = 50 where id = v_empty;
  set local role authenticated;
  begin
    perform public.add_imported_chitti_invitation(v_empty, 'Over limit', 'limit@example.com', '9000000000', 51::smallint);
    raise exception 'TEST: 51st month allowed';
  exception when others then
    if sqlerrm <> 'Choose an empty payout month or the next month, up to 50' then raise; end if;
  end;
  execute 'reset role';
  foreach v_status in array array['active', 'completed', 'cancelled']::public.chitti_status[] loop
    update public.chittis set status = v_status where id = v_empty;
    set local role authenticated;
    begin
      perform public.add_imported_chitti_invitation(v_empty, 'Wrong state', 'state@example.com', '9000000000', 3::smallint);
      raise exception 'TEST: non-pending import allowed';
    exception when others then
      if sqlerrm <> 'Payout-month invitations can only be added while an imported chitti is pending' then raise; end if;
    end;
    execute 'reset role';
  end loop;

  -- The appended member can still be reordered before activation (swap months 7 and 8).
  select jsonb_agg(jsonb_build_object('kind', kind, 'id', id) order by case position when 7 then 8 when 8 then 7 else position end)
  into v_order from (
    select 'member' as kind, user_id as id, payout_position as position from public.chitti_members where chitti_id = v_chitti and not is_admin
    union all
    select 'invitation', id, payout_position from public.invitations where chitti_id = v_chitti and status = 'pending'
  ) entries;
  set local role authenticated;
  perform public.convert_pending_chitti_to_existing(v_chitti, 3::smallint, v_order);
  execute 'reset role';
  if (select payout_position from public.invitations where id = v_invite) <> 7 then raise exception 'New member cannot be ranked'; end if;

  -- Accept all remaining invitations and activate exactly eight rounds with preserved history.
  for v_item in select id, invited_email from public.invitations where chitti_id = v_chitti and status = 'pending' loop
    select id into v_user from public.profiles where email = v_item.invited_email;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'email', v_item.invited_email)::text, true);
    set local role authenticated;
    perform public.redeem_invitation(null, v_item.id);
    execute 'reset role';
  end loop;
  set constraints invitations_activate_imported_chitti immediate;
  if not exists(select 1 from public.chittis where id = v_chitti and status = 'active' and member_count = 8) then raise exception 'Expanded import did not activate'; end if;
  if (select count(*) from public.rounds where chitti_id = v_chitti) <> 8
     or (select count(*) from public.rounds where chitti_id = v_chitti and status = 'completed') <> 3 then raise exception 'Expanded schedule or historical months incorrect'; end if;
  if not exists(select 1 from public.rounds where chitti_id = v_chitti and round_number = 7 and recipient_id = 'b9000000-0000-4000-8000-000000000008') then raise exception 'New member lost their saved rank'; end if;
  if (select count(*) from public.contributions contribution join public.rounds round_item on round_item.id = contribution.round_id where round_item.chitti_id = v_chitti) <> 40 then raise exception 'Future contribution grid incorrect'; end if;

  raise notice 'Pending imported expansion, authorization, ranking, and activation tests passed';
end;
$$;

rollback;
