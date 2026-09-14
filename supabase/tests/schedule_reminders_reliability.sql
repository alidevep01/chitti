begin;

do $$
declare
  v_admin constant uuid := '71111111-1111-4111-8111-111111111111';
  v_member constant uuid := '72222222-2222-4222-8222-222222222222';
  v_overdue_chitti constant uuid := '73333333-3333-4333-8333-333333333333';
  v_upcoming_chitti constant uuid := '74444444-4444-4444-8444-444444444444';
  v_overdue_round constant uuid := '75555555-5555-4555-8555-555555555555';
  v_upcoming_round constant uuid := '76666666-6666-4666-8666-666666666666';
  v_admin_contribution uuid;
  v_member_contribution uuid;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values
    (v_admin, 'authenticated', 'authenticated', 'schedule-test-admin@example.com', now(), '{}', '{"full_name":"Schedule admin"}', now(), now()),
    (v_member, 'authenticated', 'authenticated', 'schedule-test-member@example.com', now(), '{}', '{"full_name":"Schedule member"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = v_admin;

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, start_date,
    first_due_date, due_day, upi_id, payee_name, status, locked_at
  ) values
    (
      v_overdue_chitti, 'Overdue reminder test', v_admin, 500000, 2,
      v_today - 2, v_today - 1, extract(day from v_today - 1),
      'admin@test', 'Schedule admin', 'active', now()
    ),
    (
      v_upcoming_chitti, 'Upcoming reminder test', v_admin, 500000, 2,
      v_today, v_today + 2, extract(day from v_today + 2),
      'admin@test', 'Schedule admin', 'active', now()
    );

  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position) values
    (v_overdue_chitti, v_admin, true, 1),
    (v_overdue_chitti, v_member, false, 2),
    (v_upcoming_chitti, v_admin, true, 1),
    (v_upcoming_chitti, v_member, false, 2);

  insert into public.rounds(id, chitti_id, round_number, due_date, recipient_id, status) values
    (v_overdue_round, v_overdue_chitti, 1, v_today - 1, v_admin, 'collecting'),
    (v_upcoming_round, v_upcoming_chitti, 1, v_today + 2, v_admin, 'collecting');
  insert into public.payouts(round_id) values (v_overdue_round), (v_upcoming_round);

  insert into public.contributions(round_id, member_id, status, method, submitted_at) values
    (v_overdue_round, v_admin, 'submitted', 'cash', ((v_today - 1)::text || ' 10:00:00+05:30')::timestamptz),
    (v_overdue_round, v_member, 'due', null, null),
    (v_upcoming_round, v_admin, 'due', null, null),
    (v_upcoming_round, v_member, 'due', null, null);

  select id into v_admin_contribution
  from public.contributions
  where round_id = v_overdue_round and member_id = v_admin;
  select id into v_member_contribution
  from public.contributions
  where round_id = v_overdue_round and member_id = v_member;

  perform public.process_due_reminders();
  perform public.process_due_reminders();

  if not exists(
    select 1 from public.contributions
    where id = v_member_contribution and status = 'overdue' and overdue_at is not null
  ) then
    raise exception 'Past-due contribution was not recorded as overdue';
  end if;
  if (select count(*) from public.notifications where user_id = v_member and kind = 'contribution.overdue' and route = '/chitti/' || v_overdue_chitti) <> 1 then
    raise exception 'Daily overdue reminder was missing or duplicated';
  end if;
  if (select count(*) from public.notifications where kind = 'contribution.reminder' and route = '/chitti/' || v_upcoming_chitti) <> 2 then
    raise exception 'Upcoming daily reminders were missing or duplicated';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_member, 'email', 'schedule-test-member@example.com')::text, true);
  set local role authenticated;
  perform public.submit_contribution(v_overdue_round, 'upi', 'LATE-TEST');

  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'schedule-test-admin@example.com')::text, true);
  set local role authenticated;
  perform public.review_contribution(v_admin_contribution, true);
  perform public.review_contribution(v_member_contribution, true);

  if (select confirmed_on_time from public.contributions where id = v_admin_contribution) is not true then
    raise exception 'On-time contribution was not recorded as on time';
  end if;
  if (select confirmed_on_time from public.contributions where id = v_member_contribution) is not false then
    raise exception 'Late contribution was not recorded as late';
  end if;

  raise notice 'Schedule, daily reminder, and reliability tests passed';
end;
$$;

rollback;
