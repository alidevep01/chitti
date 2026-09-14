begin;

do $$
declare
  v_admin constant uuid := 'f1111111-1111-4111-8111-111111111111';
  v_rejector constant uuid := 'f2222222-2222-4222-8222-222222222222';
  v_observer constant uuid := 'f3333333-3333-4333-8333-333333333333';
  v_chitti constant uuid := 'f4444444-4444-4444-8444-444444444444';
  v_run constant uuid := 'f5555555-5555-4555-8555-555555555555';
  v_accept_chitti constant uuid := 'e1111111-1111-4111-8111-111111111111';
  v_accept_run constant uuid := 'e2222222-2222-4222-8222-222222222222';
  v_reason constant text := 'I need a later payout month.';
  v_snapshot jsonb;
  v_visible_reason text;
  v_reason_exposed boolean;
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values
    (v_admin, 'authenticated', 'authenticated', 'reject-test-admin@example.com', now(), '{}', '{"full_name":"Test admin"}', now(), now()),
    (v_rejector, 'authenticated', 'authenticated', 'reject-test-member@example.com', now(), '{}', '{"full_name":"Rejecting member"}', now(), now()),
    (v_observer, 'authenticated', 'authenticated', 'reject-test-observer@example.com', now(), '{}', '{"full_name":"Other member"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = v_admin;

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, first_due_date,
    due_day, upi_id, payee_name, status, shuffle_scheduled_at
  ) values (
    v_chitti, 'Rejection comment test', v_admin, 500000, 3,
    (now() at time zone 'Asia/Kolkata')::date,
    15, 'admin@test', 'Test admin', 'awaiting_approval', now()
  );
  insert into public.chitti_members(chitti_id, user_id, is_admin) values
    (v_chitti, v_admin, true),
    (v_chitti, v_rejector, false),
    (v_chitti, v_observer, false);
  insert into public.shuffle_runs(
    id, chitti_id, run_number, idempotency_key, status, result_hash, started_by
  ) values (
    v_run, v_chitti, 1, 'f6666666-6666-4666-8666-666666666666',
    'revealed', repeat('b', 64), v_admin
  );
  insert into public.shuffle_assignments(shuffle_run_id, member_id, payout_position) values
    (v_run, v_admin, 1),
    (v_run, v_rejector, 2),
    (v_run, v_observer, 3);
  insert into public.shuffle_approvals(shuffle_run_id, member_id) values
    (v_run, v_admin),
    (v_run, v_rejector),
    (v_run, v_observer);

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, first_due_date,
    due_day, upi_id, payee_name, status, shuffle_scheduled_at
  ) values (
    v_accept_chitti, 'Accepted shuffle regression test', v_admin, 500000, 3,
    (now() at time zone 'Asia/Kolkata')::date,
    15, 'admin@test', 'Test admin', 'awaiting_approval', now()
  );
  insert into public.chitti_members(chitti_id, user_id, is_admin) values
    (v_accept_chitti, v_admin, true),
    (v_accept_chitti, v_rejector, false),
    (v_accept_chitti, v_observer, false);
  insert into public.shuffle_runs(
    id, chitti_id, run_number, idempotency_key, status, result_hash, started_by
  ) values (
    v_accept_run, v_accept_chitti, 1, 'e3333333-3333-4333-8333-333333333333',
    'revealed', repeat('c', 64), v_admin
  );
  insert into public.shuffle_assignments(shuffle_run_id, member_id, payout_position) values
    (v_accept_run, v_admin, 1),
    (v_accept_run, v_rejector, 2),
    (v_accept_run, v_observer, 3);
  insert into public.shuffle_approvals(shuffle_run_id, member_id) values
    (v_accept_run, v_admin),
    (v_accept_run, v_rejector),
    (v_accept_run, v_observer);

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_rejector, 'email', 'reject-test-member@example.com')::text, true);
  set local role authenticated;
  begin
    perform public.respond_to_shuffle(v_chitti, false, null);
    raise exception 'A rejection without a comment was unexpectedly accepted';
  exception
    when others then
      if sqlerrm not like 'Please explain why%' then
        raise;
      end if;
  end;
  perform public.respond_to_shuffle(v_chitti, false, v_reason);

  if (select status from public.chittis where id = v_chitti) <> 'ready' then
    raise exception 'A rejected shuffle did not return to ready';
  end if;
  if (select reason from public.shuffle_approvals where shuffle_run_id = v_run and member_id = v_rejector) <> v_reason then
    raise exception 'The rejection comment was not saved';
  end if;

  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'reject-test-admin@example.com')::text, true);
  set local role authenticated;
  select public.get_app_snapshot() into v_snapshot;
  select member->>'approvalReason' into v_visible_reason
  from jsonb_array_elements(v_snapshot->'chittis') chitti,
       jsonb_array_elements(chitti->'members') member
  where chitti->>'id' = v_chitti::text
    and member->>'id' = v_rejector::text;
  if v_visible_reason <> v_reason then
    raise exception 'The administrator snapshot did not include the rejection comment';
  end if;
  if not exists(
    select 1 from public.notifications
    where user_id = v_admin
      and kind = 'shuffle.rejected.admin'
      and title like 'Rejecting member%'
      and message = v_reason
  ) then
    raise exception 'The administrator did not receive the named rejection notification';
  end if;

  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_observer, 'email', 'reject-test-observer@example.com')::text, true);
  set local role authenticated;
  select public.get_app_snapshot() into v_snapshot;
  select member ? 'approvalReason' into v_reason_exposed
  from jsonb_array_elements(v_snapshot->'chittis') chitti,
       jsonb_array_elements(chitti->'members') member
  where chitti->>'id' = v_chitti::text
    and member->>'id' = v_rejector::text;
  if coalesce(v_reason_exposed, false) then
    raise exception 'The rejection comment was exposed to an unrelated member';
  end if;
  if (select count(*) from public.shuffle_approvals where shuffle_run_id = v_run) <> 1 then
    raise exception 'An unrelated member could directly read other approval rows';
  end if;

  perform public.respond_to_shuffle(v_accept_chitti, true, 'This must be ignored');
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_rejector, 'email', 'reject-test-member@example.com')::text, true);
  set local role authenticated;
  perform public.respond_to_shuffle(v_accept_chitti, true, null);
  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'reject-test-admin@example.com')::text, true);
  set local role authenticated;
  perform public.respond_to_shuffle(v_accept_chitti, true, null);
  if (select status from public.chittis where id = v_accept_chitti) <> 'active'
     or (select count(*) from public.rounds where chitti_id = v_accept_chitti) <> 3 then
    raise exception 'Unanimous acceptance no longer activates the chitti';
  end if;

  raise notice 'Shuffle rejection comment and privacy tests passed';
end;
$$;

rollback;
