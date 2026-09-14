begin;

do $$
declare
  v_admin constant uuid := 'a1111111-1111-4111-8111-111111111111';
  v_first constant uuid := 'a2222222-2222-4222-8222-222222222222';
  v_second constant uuid := 'a3333333-3333-4333-8333-333333333333';
  v_late constant uuid := 'a4444444-4444-4444-8444-444444444444';
  v_chitti constant uuid := 'c1111111-1111-4111-8111-111111111111';
  v_waiting_chitti constant uuid := 'c2222222-2222-4222-8222-222222222222';
  v_waiting_run constant uuid := 'b2222222-2222-4222-8222-222222222222';
  v_round_one constant uuid := 'd1111111-1111-4111-8111-111111111111';
  v_round_two constant uuid := 'd2222222-2222-4222-8222-222222222222';
  v_round_three constant uuid := 'd3333333-3333-4333-8333-333333333333';
  v_result jsonb;
  v_reset_result jsonb;
  v_edit_result jsonb;
  v_token text;
  v_contribution uuid;
  v_adjustment uuid;
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values
    (v_admin, 'authenticated', 'authenticated', 'late-test-admin@example.com', now(), '{}', '{"full_name":"Test admin"}', now(), now()),
    (v_first, 'authenticated', 'authenticated', 'late-test-first@example.com', now(), '{}', '{"full_name":"First member"}', now(), now()),
    (v_second, 'authenticated', 'authenticated', 'late-test-second@example.com', now(), '{}', '{"full_name":"Second member"}', now(), now()),
    (v_late, 'authenticated', 'authenticated', 'late-test-new@example.com', now(), '{}', '{"full_name":"Late member"}', now(), now());

  update public.app_roles set role = 'admin' where user_id = v_admin;

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, start_date, first_due_date,
    due_day, upi_id, payee_name, status, locked_at
  ) values (
    v_chitti, 'Late join test', v_admin, 500000, 3,
    ((now() at time zone 'Asia/Kolkata')::date - interval '1 month')::date,
    ((now() at time zone 'Asia/Kolkata')::date - interval '1 month')::date,
    15, 'admin@test', 'Test admin', 'active', now()
  );

  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position) values
    (v_chitti, v_admin, true, 1),
    (v_chitti, v_first, false, 2),
    (v_chitti, v_second, false, 3);

  insert into public.rounds(id, chitti_id, round_number, due_date, recipient_id, status) values
    (v_round_one, v_chitti, 1, ((now() at time zone 'Asia/Kolkata')::date - interval '1 month')::date, v_admin, 'completed'),
    (v_round_two, v_chitti, 2, (now() at time zone 'Asia/Kolkata')::date, v_first, 'collecting'),
    (v_round_three, v_chitti, 3, ((now() at time zone 'Asia/Kolkata')::date + interval '1 month')::date, v_second, 'upcoming');

  insert into public.contributions(round_id, member_id, status, confirmed_at) values
    (v_round_one, v_admin, 'confirmed', now()),
    (v_round_one, v_first, 'confirmed', now()),
    (v_round_one, v_second, 'confirmed', now()),
    (v_round_two, v_admin, 'due', null),
    (v_round_two, v_first, 'due', null),
    (v_round_two, v_second, 'due', null),
    (v_round_three, v_admin, 'due', null),
    (v_round_three, v_first, 'due', null),
    (v_round_three, v_second, 'due', null);
  insert into public.payouts(round_id, status, paid_at) values
    (v_round_one, 'paid', now()),
    (v_round_two, 'blocked', null),
    (v_round_three, 'blocked', null);

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, first_due_date,
    due_day, upi_id, payee_name, status, shuffle_scheduled_at
  ) values (
    v_waiting_chitti, 'Unfinished shuffle test', v_admin, 500000, 2,
    (now() at time zone 'Asia/Kolkata')::date,
    15, 'admin@test', 'Test admin', 'awaiting_approval', now()
  );
  insert into public.chitti_members(chitti_id, user_id, is_admin) values
    (v_waiting_chitti, v_admin, true),
    (v_waiting_chitti, v_first, false);
  insert into public.shuffle_runs(
    id, chitti_id, run_number, idempotency_key, status, result_hash, started_by
  ) values (
    v_waiting_run, v_waiting_chitti, 1, 'e2222222-2222-4222-8222-222222222222',
    'revealed', repeat('a', 64), v_admin
  );

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'late-test-admin@example.com')::text, true);
  set local role authenticated;

  select public.add_chitti_member_invitation(
    v_waiting_chitti, 'Second member', 'late-test-second@example.com', '9111111111'
  ) into v_reset_result;
  if coalesce((v_reset_result->>'shuffle_reset')::boolean, false) is not true then
    raise exception 'Adding during approval did not report a shuffle reset';
  end if;
  if (select status from public.chittis where id = v_waiting_chitti) <> 'inviting'
     or (select member_count from public.chittis where id = v_waiting_chitti) <> 3 then
    raise exception 'Adding during approval did not return the chitti to inviting';
  end if;
  if (select status from public.shuffle_runs where id = v_waiting_run) <> 'rejected' then
    raise exception 'The unfinished shuffle was not invalidated';
  end if;
  select public.update_invitation(
    (v_reset_result->>'invitation_id')::uuid,
    'Corrected member',
    'late-test-new@example.com',
    '9222222222'
  ) into v_edit_result;
  if v_edit_result->>'token' = v_reset_result->>'token' then
    raise exception 'Editing an invitation did not rotate its link';
  end if;
  if not exists(
    select 1
    from public.invitations
    where id = (v_reset_result->>'invitation_id')::uuid
      and invited_name = 'Corrected member'
      and invited_email = 'late-test-new@example.com'
      and invited_phone = '9222222222'
      and token_hash = extensions.digest(v_edit_result->>'token', 'sha256')
  ) then
    raise exception 'Edited invitation details or token were not saved';
  end if;

  select public.add_chitti_member_invitation(
    v_chitti, 'Late member', 'late-test-new@example.com', '9000000000'
  ) into v_result;
  v_token := v_result->>'token';
  if coalesce((v_result->>'late_join')::boolean, false) is not true then
    raise exception 'Active invitation was not marked as a late join';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_late, 'email', 'late-test-new@example.com')::text, true);
  perform public.redeem_invitation(v_token, null);

  if (select member_count from public.chittis where id = v_chitti) <> 4 then
    raise exception 'Late join did not increase the member count';
  end if;
  if (select payout_position from public.chitti_members where chitti_id = v_chitti and user_id = v_late) <> 4 then
    raise exception 'Late member was not assigned the final payout month';
  end if;
  if (select count(*) from public.rounds where chitti_id = v_chitti) <> 4 then
    raise exception 'Late join did not append a payout round';
  end if;
  if (select count(*) from public.contributions c join public.rounds r on r.id = c.round_id where r.chitti_id = v_chitti and c.member_id = v_late) <> 4 then
    raise exception 'Late member did not receive all required contributions';
  end if;
  if (select count(*) from public.payout_adjustments where chitti_id = v_chitti and source_member_id = v_late) <> 1 then
    raise exception 'Completed recipient did not receive a catch-up payout adjustment';
  end if;

  select c.id into v_contribution
  from public.contributions c where c.round_id = v_round_one and c.member_id = v_late;
  perform public.submit_contribution(v_round_one, 'upi', 'TEST-CATCHUP');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'late-test-admin@example.com')::text, true);
  perform public.review_contribution(v_contribution, true);
  select id into v_adjustment from public.payout_adjustments
  where contribution_id = v_contribution;
  if (select status from public.payout_adjustments where id = v_adjustment) <> 'ready' then
    raise exception 'Confirmed catch-up contribution did not make the top-up ready';
  end if;
  perform public.confirm_payout_adjustment(v_adjustment, 'TEST-TOPUP');
  if (select status from public.payout_adjustments where id = v_adjustment) <> 'paid' then
    raise exception 'Top-up could not be marked paid';
  end if;

  perform public.swap_payout_months(v_chitti, v_first, v_second);
  if (select payout_position from public.chitti_members where chitti_id = v_chitti and user_id = v_first) <> 3
     or (select payout_position from public.chitti_members where chitti_id = v_chitti and user_id = v_second) <> 2 then
    raise exception 'Member payout positions were not swapped';
  end if;
  if (select recipient_id from public.rounds where id = v_round_two) <> v_second
     or (select recipient_id from public.rounds where id = v_round_three) <> v_first then
    raise exception 'Round recipients were not swapped';
  end if;
  execute 'reset role';
  if exists(
    select 1 from public.notifications
    where user_id = v_second
      and dedupe_key = 'invite:' || (v_reset_result->>'invitation_id')
  ) or not exists(
    select 1 from public.notifications
    where user_id = v_late
      and dedupe_key = 'invite:' || (v_reset_result->>'invitation_id')
  ) then
    raise exception 'Editing the email did not move the in-app invitation notification';
  end if;
  if (select count(*) from public.notifications where user_id in (v_first, v_second) and kind = 'payout.month_changed') <> 2 then
    raise exception 'Affected members did not both receive notifications';
  end if;

  raise notice 'Late-member catch-up, top-up, and month-swap tests passed';
end;
$$;

rollback;
