begin;

do $$
declare
  v_admin constant uuid := 'a9111111-1111-4111-8111-111111111111';
  v_active_chitti constant uuid := 'a9222222-2222-4222-8222-222222222222';
  v_result jsonb;
  v_add_result jsonb;
  v_chitti uuid;
  v_snapshot jsonb;
  v_snapshot_chitti jsonb;
  v_failed boolean := false;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values (
    v_admin, 'authenticated', 'authenticated', 'incremental-admin@example.com', now(), '{}',
    '{"full_name":"Incremental admin"}', now(), now()
  );
  update public.app_roles set role = 'admin' where user_id = v_admin;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_admin, 'email', 'incremental-admin@example.com')::text,
    true
  );
  set local role authenticated;

  select public.import_existing_chitti(jsonb_build_object(
    'name', 'Partially entered old chitti',
    'description', 'Thirteen slots can be filled gradually',
    'monthlyAmountPaise', 500000,
    'memberCount', 13,
    'completedMonths', 2,
    'startDate', v_today - 60,
    'firstDueDate', v_today - 60,
    'dueDay', extract(day from v_today - 60)::int,
    'upiId', 'incremental-admin@upi',
    'payeeName', 'Incremental admin',
    'invites', jsonb_build_array(
      jsonb_build_object(
        'name', 'Month five member',
        'email', 'month-five@example.com',
        'phone', '+91 90000 00005',
        'payoutPosition', 5
      )
    )
  )) into v_result;
  v_chitti := (v_result->>'chitti_id')::uuid;

  if not exists (
    select 1 from public.chittis
    where id = v_chitti and member_count = 13 and status = 'inviting' and is_imported
  ) then
    raise exception 'A partially entered imported chitti was not created correctly';
  end if;
  if (select count(*) from public.invitations where chitti_id = v_chitti) <> 1
     or not exists (
       select 1 from public.invitations
       where chitti_id = v_chitti and payout_position = 5
     ) then
    raise exception 'The initial sparse payout-month invitation was not saved';
  end if;

  select public.add_imported_chitti_invitation(
    v_chitti, 'Month two member', 'month-two@example.com', '+91 90000 00002', 2::smallint
  ) into v_add_result;
  if (v_add_result->>'payout_position')::int <> 2 then
    raise exception 'The later invitation did not retain payout month 2';
  end if;
  perform public.add_imported_chitti_invitation(
    v_chitti, 'Month thirteen member', 'month-thirteen@example.com', '+91 90000 00013', 13::smallint
  );
  if (select member_count from public.chittis where id = v_chitti) <> 13 then
    raise exception 'Adding a missing imported member changed the planned member count';
  end if;

  begin
    perform public.add_imported_chitti_invitation(
      v_chitti, 'Duplicate month', 'duplicate-month@example.com', '+91 90000 00113', 13::smallint
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'A duplicate imported payout month was accepted';
  end if;

  select public.get_app_snapshot() into v_snapshot;
  select value into v_snapshot_chitti
  from jsonb_array_elements(v_snapshot->'chittis')
  where value->>'id' = v_chitti::text;
  if not exists (
    select 1
    from jsonb_array_elements(v_snapshot_chitti->'invitations') invitation
    where invitation->>'email' = 'month-five@example.com'
      and (invitation->>'payoutPosition')::int = 5
  ) then
    raise exception 'The application snapshot omitted an invitation payout month';
  end if;

  perform public.cancel_chitti(v_chitti);
  if not exists (
    select 1 from public.chittis
    where id = v_chitti and status = 'cancelled' and archived_at is not null
  ) then
    raise exception 'The pending chitti was not cancelled and archived';
  end if;
  if exists (
    select 1 from public.invitations
    where chitti_id = v_chitti and status = 'pending'
  ) then
    raise exception 'Cancelling the chitti left working invitation links';
  end if;

  execute 'reset role';
  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, start_date,
    first_due_date, due_day, upi_id, payee_name, status, locked_at
  ) values (
    v_active_chitti, 'Active cannot delete', v_admin, 500000, 2, v_today,
    v_today, extract(day from v_today), 'incremental-admin@upi', 'Incremental admin',
    'active', now()
  );
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_admin, 'email', 'incremental-admin@example.com')::text,
    true
  );
  set local role authenticated;
  v_failed := false;
  begin
    perform public.cancel_chitti(v_active_chitti);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'An active chitti was incorrectly allowed to be deleted';
  end if;

  raise notice 'Incremental existing-member invitations and pending chitti cancellation tests passed';
end;
$$;

rollback;
