begin;

do $$
declare
  v_admin constant uuid := '91111111-1111-4111-8111-111111111111';
  v_owner constant uuid := '92222222-2222-4222-8222-222222222222';
  v_coowner constant uuid := '93333333-3333-4333-8333-333333333333';
  v_chitti constant uuid := '94444444-4444-4444-8444-444444444444';
  v_round constant uuid := '95555555-5555-4555-8555-555555555555';
  v_result jsonb;
  v_token text;
  v_first_share uuid;
  v_second_share uuid;
  v_snapshot jsonb;
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values
    (v_admin, 'authenticated', 'authenticated', 'shared-admin@example.com', now(), '{}', '{"full_name":"Shared admin"}', now(), now()),
    (v_owner, 'authenticated', 'authenticated', 'shared-owner@example.com', now(), '{}', '{"full_name":"Original owner"}', now(), now()),
    (v_coowner, 'authenticated', 'authenticated', 'shared-coowner@example.com', now(), '{}', '{"full_name":"Co owner"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = v_admin;

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, start_date,
    first_due_date, due_day, upi_id, payee_name, status, locked_at
  ) values (
    v_chitti, 'Shared payout test', v_admin, 500000, 2, (current_date - interval '1 month')::date,
    (current_date - interval '1 month')::date, extract(day from current_date), 'admin@test', 'Shared admin', 'active', now()
  );
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position) values
    (v_chitti, v_admin, true, 1),
    (v_chitti, v_owner, false, 2);
  insert into public.rounds(id, chitti_id, round_number, due_date, recipient_id, status)
  values (v_round, v_chitti, 2, current_date, v_owner, 'collecting');
  insert into public.payouts(round_id, status) values (v_round, 'blocked');
  insert into public.contributions(round_id, member_id, status) values
    (v_round, v_admin, 'due'),
    (v_round, v_owner, 'due');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'shared-admin@example.com')::text, true);
  set local role authenticated;
  select public.add_coowner_invitation(
    v_chitti, v_owner, 4000::smallint, 'Co owner', 'shared-coowner@example.com', '9000000000'
  ) into v_result;
  v_token := v_result->>'token';

  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_coowner, 'email', 'shared-coowner@example.com')::text, true);
  set local role authenticated;
  perform public.redeem_invitation(v_token, null);

  execute 'reset role';

  if (select contribution_share_bps from public.chitti_members where chitti_id = v_chitti and user_id = v_owner) <> 6000
     or (select contribution_share_bps from public.chitti_members where chitti_id = v_chitti and user_id = v_coowner) <> 4000 then
    raise exception 'The ownership percentages were not split correctly';
  end if;
  if (select amount_paise from public.contributions where round_id = v_round and member_id = v_owner) <> 300000
     or (select amount_paise from public.contributions where round_id = v_round and member_id = v_coowner) <> 200000 then
    raise exception 'The proportional contribution amounts were not created';
  end if;
  if (select sum(amount_paise) from public.round_payout_shares where round_id = v_round) <> 1000000
     or (select count(*) from public.round_payout_shares where round_id = v_round) <> 2 then
    raise exception 'The proportional payout records do not equal the full pot: sum %, count %',
      (select sum(amount_paise) from public.round_payout_shares where round_id = v_round),
      (select count(*) from public.round_payout_shares where round_id = v_round);
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_coowner, 'email', 'shared-coowner@example.com')::text, true);
  set local role authenticated;
  select public.get_app_snapshot() into v_snapshot;
  if not exists(
    select 1
    from jsonb_array_elements(v_snapshot->'chittis'->0->'rounds'->0->'payoutShares') share
    where (share->>'recipientMemberId')::uuid = v_coowner and (share->>'amountPaise')::bigint = 400000
  ) then
    raise exception 'The co-owner payout was missing from the application snapshot';
  end if;

  execute 'reset role';
  update public.contributions set status = 'confirmed', confirmed_at = now() where round_id = v_round;
  update public.rounds set status = 'ready_for_payout' where id = v_round;
  update public.payouts set status = 'ready' where round_id = v_round;
  update public.round_payout_shares set status = 'ready' where round_id = v_round;
  select id into v_first_share from public.round_payout_shares where round_id = v_round and recipient_id = v_owner;
  select id into v_second_share from public.round_payout_shares where round_id = v_round and recipient_id = v_coowner;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'shared-admin@example.com')::text, true);
  set local role authenticated;
  perform public.confirm_payout_share(v_first_share, 'FIRST');
  if (select status from public.payouts where round_id = v_round) <> 'ready'
     or (select status from public.rounds where id = v_round) <> 'ready_for_payout' then
    raise exception 'The first confirmation completed the round too early';
  end if;
  perform public.confirm_payout_share(v_second_share, 'SECOND');
  if (select status from public.payouts where round_id = v_round) <> 'paid'
     or (select status from public.rounds where id = v_round) <> 'completed' then
    raise exception 'The second confirmation did not complete the shared payout';
  end if;

  raise notice 'Shared contribution and separate proportional payout tests passed';
end;
$$;

rollback;
