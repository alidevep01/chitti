begin;

do $$
declare
  v_admin constant uuid := '91111111-1111-4111-8111-111111111111';
  v_second constant uuid := '92222222-2222-4222-8222-222222222222';
  v_third constant uuid := '93333333-3333-4333-8333-333333333333';
  v_result jsonb;
  v_chitti uuid;
  v_second_token text;
  v_third_token text;
  v_snapshot jsonb;
  v_imported jsonb;
  v_start date := ((now() at time zone 'Asia/Kolkata')::date - interval '2 months')::date;
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values
    (v_admin, 'authenticated', 'authenticated', 'import-test-admin@example.com', now(), '{}', '{"full_name":"Import admin"}', now(), now()),
    (v_second, 'authenticated', 'authenticated', 'import-test-second@example.com', now(), '{}', '{"full_name":"Second member"}', now(), now()),
    (v_third, 'authenticated', 'authenticated', 'import-test-third@example.com', now(), '{}', '{"full_name":"Third member"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = v_admin;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_admin, 'email', 'import-test-admin@example.com')::text,
    true
  );
  set local role authenticated;

  select public.import_existing_chitti(jsonb_build_object(
    'name', 'Existing family chitti',
    'description', 'Imported after its first payout',
    'monthlyAmountPaise', 500000,
    'memberCount', 3,
    'completedMonths', 1,
    'startDate', v_start,
    'firstDueDate', v_start,
    'dueDay', extract(day from v_start)::int,
    'upiId', 'import-admin@upi',
    'payeeName', 'Import admin',
    'invites', jsonb_build_array(
      jsonb_build_object(
        'name', 'Second member',
        'email', 'import-test-second@example.com',
        'phone', '+91 90000 00002',
        'payoutPosition', 2
      ),
      jsonb_build_object(
        'name', 'Third member',
        'email', 'import-test-third@example.com',
        'phone', '+91 90000 00003',
        'payoutPosition', 3
      )
    )
  )) into v_result;

  v_chitti := (v_result->>'chitti_id')::uuid;
  v_second_token := v_result->'invitations'->0->>'token';
  v_third_token := v_result->'invitations'->1->>'token';

  execute 'reset role';
  if not exists (
    select 1 from public.chittis
    where id = v_chitti
      and is_imported
      and imported_completed_months = 1
      and status = 'inviting'
  ) then
    raise exception 'Imported chitti metadata was not saved';
  end if;
  if (select array_agg(payout_position order by payout_position) from public.invitations where chitti_id = v_chitti)
     <> array[2::smallint, 3::smallint] then
    raise exception 'Invitation payout positions were not preserved';
  end if;
  if exists (select 1 from public.rounds where chitti_id = v_chitti) then
    raise exception 'Rounds were created before all invited members joined';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_second, 'email', 'import-test-second@example.com')::text,
    true
  );
  set local role authenticated;
  perform public.redeem_invitation(v_second_token, null);
  execute 'reset role';

  if not exists (
    select 1 from public.chitti_members
    where chitti_id = v_chitti and user_id = v_second and payout_position = 2
  ) then
    raise exception 'The first accepted invitation did not retain payout month 2';
  end if;
  if exists (select 1 from public.rounds where chitti_id = v_chitti) then
    raise exception 'Rounds were created before the final member joined';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_third, 'email', 'import-test-third@example.com')::text,
    true
  );
  set local role authenticated;
  perform public.redeem_invitation(v_third_token, null);
  set constraints invitations_activate_imported_chitti immediate;
  execute 'reset role';

  if not exists (select 1 from public.chittis where id = v_chitti and status = 'active' and locked_at is not null) then
    raise exception 'The imported chitti did not activate after its final member joined (status %, positioned members %, rounds %, locked %)',
      (select status from public.chittis where id = v_chitti),
      (select count(*) from public.chitti_members where chitti_id = v_chitti and payout_position is not null),
      (select count(*) from public.rounds where chitti_id = v_chitti),
      (select locked_at from public.chittis where id = v_chitti);
  end if;
  if (select count(*) from public.rounds where chitti_id = v_chitti) <> 3 then
    raise exception 'The imported chitti did not create one round per member';
  end if;
  if not exists (
    select 1 from public.rounds round_item
    join public.payouts payout on payout.round_id = round_item.id
    where round_item.chitti_id = v_chitti
      and round_item.round_number = 1
      and round_item.status = 'completed'
      and payout.status = 'paid'
  ) then
    raise exception 'The historical round was not marked completed and paid';
  end if;
  if exists (
    select 1 from public.contributions contribution
    join public.rounds round_item on round_item.id = contribution.round_id
    where round_item.chitti_id = v_chitti and round_item.round_number = 1
  ) then
    raise exception 'Historical payments were created and could incorrectly affect reliability';
  end if;
  if (select count(*) from public.contributions contribution
      join public.rounds round_item on round_item.id = contribution.round_id
      where round_item.chitti_id = v_chitti) <> 6 then
    raise exception 'Current and future contribution rows were not created correctly';
  end if;
  if not exists (
    select 1 from public.rounds
    where chitti_id = v_chitti and round_number = 2 and status = 'collecting' and recipient_id = v_second
  ) or not exists (
    select 1 from public.rounds
    where chitti_id = v_chitti and round_number = 3 and status = 'upcoming' and recipient_id = v_third
  ) then
    raise exception 'The current/future round state or saved payout order was incorrect';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_admin, 'email', 'import-test-admin@example.com')::text,
    true
  );
  set local role authenticated;
  select public.get_app_snapshot() into v_snapshot;
  select value into v_imported
  from jsonb_array_elements(v_snapshot->'chittis')
  where value->>'id' = v_chitti::text;
  if v_imported->>'isImported' <> 'true'
     or (v_imported->>'importedCompletedMonths')::int <> 1 then
    raise exception 'Imported metadata was missing from the application snapshot: %', v_imported;
  end if;

  raise notice 'Existing chitti import, fixed order, activation, and historical reliability tests passed';
end;
$$;

rollback;
