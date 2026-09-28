begin;
do $$
#variable_conflict use_variable
declare
  admin_id uuid := 'c9111111-1111-4111-8111-111111111111';
  chitti_id uuid := 'c9222222-2222-4222-8222-222222222222';
  owner_id uuid := 'c9000000-0000-4000-8000-000000000002';
  main_invite uuid;
  first_child uuid;
  second_child uuid;
  invited_child uuid;
  admin_child uuid;
  result jsonb;
  snapshot jsonb;
  person uuid;
  shared_round uuid;
  share_id uuid;
  item record;
begin
  insert into auth.users(id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (admin_id, 'authenticated', 'authenticated', 'pending-share-admin@example.com', now(), '{}', '{"full_name":"Admin"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = admin_id;
  for i in 2..8 loop
    person := ('c9000000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    insert into auth.users(id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (person, 'authenticated', 'authenticated', 'pending-share-' || i || '@example.com', now(), '{}', '{"full_name":"Shared member"}', now(), now());
  end loop;
  insert into public.chittis(id, name, admin_id, monthly_amount_paise, member_count, start_date, first_due_date, due_day, upi_id, payee_name, status, is_imported, imported_completed_months)
  values (chitti_id, 'Pending shared positions', admin_id, 2000001, 3, '2026-01-31', '2026-01-31', 31, 'admin@test', 'Admin', 'inviting', true, 1);
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position)
  values (chitti_id, admin_id, true, 1), (chitti_id, owner_id, false, 2);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', admin_id, 'email', 'pending-share-admin@example.com')::text, true);
  set local role authenticated;
  result := public.add_imported_chitti_invitation(chitti_id, 'Main owner', 'pending-share-3@example.com', '9000000000', 3::smallint);
  main_invite := (result->>'invitation_id')::uuid;
  result := public.add_coowner_invitation(chitti_id, owner_id, 3333::smallint, 'Child four', 'pending-share-4@example.com', '9000000000');
  first_child := (result->>'invitation_id')::uuid;
  result := public.add_coowner_invitation(chitti_id, owner_id, 3333::smallint, 'Child five', 'pending-share-5@example.com', '9000000000');
  second_child := (result->>'invitation_id')::uuid;
  begin
    perform public.add_coowner_invitation(chitti_id, owner_id, 4000::smallint, 'Over budget', 'pending-share-8@example.com', '9000000000');
    raise exception 'TEST: reserved amount was exceeded';
  exception when others then if sqlerrm not like 'Enter a positive amount below%' then raise; end if; end;
  result := public.add_coowner_invitation(chitti_id, null, 5000::smallint, 'Child six', 'pending-share-6@example.com', '9000000000', main_invite);
  invited_child := (result->>'invitation_id')::uuid;
  begin
    perform public.add_coowner_invitation(chitti_id, null, 5001::smallint, 'Oversubscribed', 'pending-share-8@example.com', '9000000000', main_invite);
    raise exception 'TEST: pending shares could exceed 100 percent';
  exception when others then if sqlerrm not like 'Enter a positive amount below%' then raise; end if; end;
  result := public.add_coowner_invitation(chitti_id, admin_id, 2500::smallint, 'Admin child', 'pending-share-7@example.com', '9000000000');
  admin_child := (result->>'invitation_id')::uuid;
  execute 'reset role';
  if (select member_count from public.chittis where id = chitti_id) <> 3 then raise exception 'Sharing grew the schedule'; end if;
  -- Non-admin calls and helper bypasses are forbidden.
  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_id, 'email', 'pending-share-2@example.com')::text, true);
  set local role authenticated;
  begin
    perform public.add_coowner_invitation(chitti_id, admin_id, 100::smallint, 'Forbidden', 'pending-share-8@example.com', '9000000000');
    raise exception 'TEST: non-admin invitation allowed';
  exception when others then if sqlerrm <> 'Administrator access required' then raise; end if; end;
  if has_function_privilege('authenticated', 'public.add_coowner_invitation_active(uuid,uuid,smallint,text,text,text)', 'execute') then raise exception 'Legacy bypass exposed'; end if;
  execute 'reset role';
  -- Co-owner accepts BEFORE their main owner; another accepts after their main owner.
  perform set_config('request.jwt.claims', '{"sub":"c9000000-0000-4000-8000-000000000006","email":"pending-share-6@example.com"}', true);
  set local role authenticated;
  snapshot := public.get_app_snapshot();
  if not exists(select 1 from jsonb_array_elements(snapshot->'pendingInvitations') entry where entry->>'id' = invited_child::text and (entry->>'coOwnerAmountPaise')::bigint = 1000000 and (entry->>'contributionAmountPaise')::bigint = 1000000) then raise exception 'Shared invitation preview missing'; end if;
  perform public.redeem_invitation(null, invited_child);
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"c9000000-0000-4000-8000-000000000004","email":"pending-share-4@example.com"}', true);
  set local role authenticated;
  perform public.redeem_invitation(null, first_child);
  execute 'reset role';
  -- Reorder whole positions, including accepted children, invited parents and pending children.
  perform set_config('request.jwt.claims', jsonb_build_object('sub', admin_id, 'email', 'pending-share-admin@example.com')::text, true);
  set local role authenticated;
  perform public.convert_pending_chitti_to_existing(chitti_id, 1::smallint, jsonb_build_array(
    jsonb_build_object('kind', 'invitation', 'id', main_invite), jsonb_build_object('kind', 'member', 'id', owner_id)));
  execute 'reset role';
  if not exists(select 1 from public.chitti_members m where m.chitti_id = chitti_id and m.user_id = owner_id and payout_position = 3)
    or not exists(select 1 from public.chitti_members m where m.chitti_id = chitti_id and m.user_id = 'c9000000-0000-4000-8000-000000000006' and payout_position = 2)
    or exists(select 1 from public.invitations where id in (first_child, second_child) and payout_position <> 3)
    or exists(select 1 from public.invitations where id in (main_invite, invited_child) and payout_position <> 2)
    or (select payout_position from public.invitations where id = admin_child) <> 1 then raise exception 'Shared ranking split co-owners'; end if;
  perform set_config('request.jwt.claims', '{"sub":"c9000000-0000-4000-8000-000000000003","email":"pending-share-3@example.com"}', true);
  set local role authenticated;
  perform public.redeem_invitation(null, main_invite);
  execute 'reset role';
  perform public.activate_imported_chitti(chitti_id);
  if (select status from public.chittis where id = chitti_id) <> 'inviting' then raise exception 'Activated while co-owners still invited'; end if;
  if (select contribution_share_bps from public.chitti_members m where m.chitti_id = chitti_id and user_id = 'c9000000-0000-4000-8000-000000000003') <> 5000 then raise exception 'Main owner did not retain correct share'; end if;
  -- Accept remaining children, then flush the deferred activation trigger.
  for item in select * from (values (second_child, 5), (admin_child, 7)) v(invite, num) loop
    person := ('c9000000-0000-4000-8000-' || lpad(item.num::text, 12, '0'))::uuid;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', person, 'email', 'pending-share-' || item.num || '@example.com')::text, true);
    set local role authenticated;
    perform public.redeem_invitation(null, item.invite);
    execute 'reset role';
  end loop;
  set constraints all immediate;
  if (select status from public.chittis where id = chitti_id) <> 'active' then raise exception 'Shared chitti did not activate'; end if;
  if (select count(*) from public.rounds r where r.chitti_id = chitti_id) <> 3 then raise exception 'Round count must equal positions not people'; end if;
  if exists(select 1 from public.rounds r join public.contributions c on c.round_id = r.id where r.chitti_id = chitti_id and r.round_number = 1) then raise exception 'Historical contributions were fabricated'; end if;
  if exists(select 1 from public.rounds r join public.round_payout_shares s on s.round_id = r.id where r.chitti_id = chitti_id and r.round_number = 1 and s.status <> 'paid') then raise exception 'Historical shares must stay paid'; end if;
  if exists(select 1 from public.chitti_members m where m.chitti_id = chitti_id group by payout_position having sum(contribution_amount_paise) <> 2000001) then raise exception 'Invalid final amount totals'; end if;
  if exists(select 1 from public.rounds r join public.contributions c on c.round_id = r.id where r.chitti_id = chitti_id group by r.id having sum(c.amount_paise) <> 6000003 or count(*) <> 7) then raise exception 'Proportional contributions lose paise or members'; end if;
  if exists(select 1 from public.rounds r join public.round_payout_shares s on s.round_id = r.id where r.chitti_id = chitti_id group by r.id having sum(s.amount_paise) <> 6000003) then raise exception 'Payout shares lose paise'; end if;
  select id into shared_round from public.rounds r where r.chitti_id = chitti_id and round_number = 2;
  update public.contributions set status = 'confirmed' where round_id = shared_round;
  update public.rounds set status = 'ready_for_payout' where id = shared_round;
  update public.payouts set status = 'ready' where round_id = shared_round;
  update public.round_payout_shares set status = 'ready' where round_id = shared_round;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', admin_id, 'email', 'pending-share-admin@example.com')::text, true);
  set local role authenticated;
  select id into share_id from public.round_payout_shares where round_id = shared_round order by id limit 1;
  perform public.confirm_payout_share(share_id);
  if (select status from public.rounds where id = shared_round) = 'completed' then raise exception 'First confirmation completed both payouts'; end if;
  select id into share_id from public.round_payout_shares where round_id = shared_round and status <> 'paid' limit 1;
  perform public.confirm_payout_share(share_id);
  if (select status from public.rounds where id = shared_round) <> 'completed' then raise exception 'Separate payouts did not complete'; end if;
  execute 'reset role';
  -- The invited main owner can also accept first. Their child's source stays resolvable.
  chitti_id := 'c9333333-3333-4333-8333-333333333333';
  insert into public.chittis(id, name, admin_id, monthly_amount_paise, member_count, start_date, first_due_date, due_day, upi_id, payee_name, status, is_imported, imported_completed_months)
  values (chitti_id, 'Main accepts first', admin_id, 2000000, 2, '2026-01-01', '2026-01-01', 1, 'admin@test', 'Admin', 'inviting', true, 0);
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position) values (chitti_id, admin_id, true, 1);
  set local role authenticated;
  result := public.add_imported_chitti_invitation(chitti_id, 'Main owner', 'pending-share-3@example.com', '9000000000', 2::smallint);
  main_invite := (result->>'invitation_id')::uuid;
  result := public.add_coowner_invitation(chitti_id, null, 5000::smallint, 'Child six', 'pending-share-6@example.com', '9000000000', main_invite);
  invited_child := (result->>'invitation_id')::uuid;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"c9000000-0000-4000-8000-000000000003","email":"pending-share-3@example.com"}', true);
  set local role authenticated;
  perform public.redeem_invitation(null, main_invite);
  if (select status from public.chittis where id = chitti_id) <> 'inviting' then raise exception 'Main-first import activated too early'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claims', '{"sub":"c9000000-0000-4000-8000-000000000006","email":"pending-share-6@example.com"}', true);
  set local role authenticated;
  perform public.redeem_invitation(null, invited_child);
  execute 'reset role';
  if (select status from public.chittis where id = chitti_id) <> 'active'
     or (select count(*) from public.chitti_members m where m.chitti_id = chitti_id and contribution_share_bps = 5000) <> 2 then raise exception 'Main-first shared activation failed'; end if;
  raise notice 'Pending shared positions, acceptance order, grouped ranking, exact amounts and separate payouts passed';
end;
$$;
rollback;
