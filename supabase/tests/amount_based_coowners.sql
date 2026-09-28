begin;
do $$
#variable_conflict use_variable
declare
  admin_id uuid := 'd9111111-1111-4111-8111-111111111111';
  chitti_id uuid := 'd9222222-2222-4222-8222-222222222222';
  parent_id uuid; person uuid; result jsonb; snapshot jsonb; invite_ids uuid[] := '{}';
  amounts bigint[] := array[500000, 123456, 200000, 1, 666667];
  item record; round_id uuid; share_id uuid; second_chitti uuid := 'd9333333-3333-4333-8333-333333333333';
begin
  insert into auth.users(id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values(admin_id, 'authenticated','authenticated','amount-admin@example.com',now(),'{}','{"full_name":"Admin"}',now(),now());
  update public.app_roles set role = 'admin' where user_id = admin_id;
  for i in 2..10 loop
    person := ('d9000000-0000-4000-8000-' || lpad(i::text,12,'0'))::uuid;
    insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    values(person,'authenticated','authenticated','amount-' || i || '@example.com',now(),'{}','{"full_name":"Owner"}',now(),now());
  end loop;
  insert into public.chittis(id,name,admin_id,monthly_amount_paise,member_count,start_date,first_due_date,due_day,upi_id,payee_name,status,is_imported,imported_completed_months)
  values(chitti_id,'Many unequal co-owners',admin_id,2000000,2,'2026-01-01','2026-01-01',1,'admin@test','Admin','inviting',true,0),
    (second_chitti,'Exact thirds',admin_id,2000000,2,'2026-01-01','2026-01-01',1,'admin@test','Admin','inviting',true,0);
  insert into public.chitti_members(chitti_id,user_id,is_admin,payout_position) values(chitti_id,admin_id,true,1),(second_chitti,admin_id,true,1);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email','amount-admin@example.com')::text,true);
  set local role authenticated;
  result := public.add_imported_chitti_invitation(chitti_id,'Main owner','amount-2@example.com','9000000000',2::smallint);
  parent_id := (result->>'invitation_id')::uuid;
  for i in 1..5 loop
    result := public.add_coowner_amount_invitation(chitti_id,null,amounts[i],'Co-owner ' || i,'amount-' || (i+2) || '@example.com','9000000000',parent_id);
    invite_ids := array_append(invite_ids,(result->>'invitation_id')::uuid);
  end loop;
  -- No three-person cap: five new co-owners plus the original share one month.
  if cardinality(invite_ids) <> 5 or (select member_count from public.chittis where id = chitti_id) <> 2 then raise exception 'Sharing changed capacity or capped owners'; end if;
  begin
    perform public.add_coowner_amount_invitation(chitti_id,null,509876,'Over reserved','amount-8@example.com','9000000000',parent_id);
    raise exception 'TEST: oversubscription accepted';
  exception when others then if sqlerrm not like 'Enter a positive amount below%' then raise; end if; end;
  foreach person in array array['d9000000-0000-4000-8000-000000000008'::uuid] loop
    execute 'reset role';
    perform set_config('request.jwt.claims',jsonb_build_object('sub',person,'email','amount-8@example.com')::text,true);
    set local role authenticated;
    begin
      perform public.add_coowner_amount_invitation(chitti_id,null,100,'Not admin','amount-9@example.com','9000000000',parent_id);
      raise exception 'TEST: non-admin could allocate';
    exception when others then if sqlerrm <> 'Administrator access required' then raise; end if; end;
  end loop;
  -- Child-first and exact one-paise shares, not rounded percentage shares.
  for i in 1..5 loop
    execute 'reset role';
    person := ('d9000000-0000-4000-8000-' || lpad((i+2)::text,12,'0'))::uuid;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',person,'email','amount-' || (i+2) || '@example.com')::text,true);
    set local role authenticated;
    perform public.redeem_invitation(null,invite_ids[i]);
  end loop;
  execute 'reset role';
  perform set_config('request.jwt.claims','{"sub":"d9000000-0000-4000-8000-000000000002","email":"amount-2@example.com"}',true);
  set local role authenticated;
  snapshot := public.get_app_snapshot();
  if not exists(select 1 from jsonb_array_elements(snapshot->'pendingInvitations') e where e->>'id' = parent_id::text and (e->>'contributionAmountPaise')::bigint = 509876) then raise exception 'Main-owner remaining preview is wrong'; end if;
  perform public.redeem_invitation(null,parent_id);
  execute 'reset role';
  set constraints all immediate;
  if (select status from public.chittis where id = chitti_id) <> 'active' then raise exception 'Many-owner activation failed'; end if;
  if (select count(*) from public.rounds r where r.chitti_id = chitti_id) <> 2 then raise exception 'People incorrectly created extra months'; end if;
  if exists(select 1 from public.rounds r join public.contributions x on x.round_id = r.id where r.chitti_id = chitti_id group by r.id having sum(x.amount_paise) <> 4000000 or count(*) <> 7) then raise exception 'Exact contribution totals failed'; end if;
  select id into round_id from public.rounds r where r.chitti_id = chitti_id and round_number = 2;
  if (select count(*) from public.round_payout_shares s where s.round_id = round_id) <> 6 or (select sum(amount_paise) from public.round_payout_shares s where s.round_id = round_id) <> 4000000 then raise exception 'Exact payout totals failed'; end if;
  if not exists(select 1 from public.chitti_members m where m.chitti_id = chitti_id and user_id = 'd9000000-0000-4000-8000-000000000006' and contribution_amount_paise = 1) then raise exception 'One-paise contribution was rounded'; end if;
  update public.contributions x set status='confirmed' where x.round_id=round_id;
  update public.rounds set status='ready_for_payout' where id=round_id;
  update public.payouts p set status='ready' where p.round_id=round_id;
  update public.round_payout_shares s set status='ready' where s.round_id=round_id;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email','amount-admin@example.com')::text,true);
  set local role authenticated;
  for item in select id from public.round_payout_shares s where s.round_id=round_id order by id loop
    perform public.confirm_payout_share(item.id);
    if exists(select 1 from public.round_payout_shares s where s.round_id=round_id and status <> 'paid') and (select status from public.rounds where id=round_id)='completed' then raise exception 'Payout completed with unpaid co-owners'; end if;
  end loop;
  if (select status from public.rounds where id=round_id)<>'completed' then raise exception 'Final payout not completed'; end if;
  snapshot := public.get_reports();
  if not exists(select 1 from jsonb_array_elements(snapshot) report,
    lateral jsonb_array_elements(report->'chittis') history
    where report->>'userId'='d9000000-0000-4000-8000-000000000006' and history->>'chittiId'=chitti_id::text
      and (report->>'confirmedAmountPaise')::bigint=1 and (history->>'monthlyAmountPaise')::bigint=1
      and history->>'payoutStatus'='paid' and history->>'payoutDate' is not null) then raise exception 'Reports lost exact amounts or co-owner payout details'; end if;
  -- Exact thirds: two invitations at 6666.67, remainder 6666.66. Parent accepts first.
  result := public.add_imported_chitti_invitation(second_chitti,'Main owner','amount-2@example.com','9000000000',2::smallint);
  parent_id := (result->>'invitation_id')::uuid;
  invite_ids := '{}';
  for i in 3..4 loop
    result := public.add_coowner_amount_invitation(second_chitti,null,666667,'Third owner','amount-' || i || '@example.com','9000000000',parent_id);
    invite_ids := array_append(invite_ids,(result->>'invitation_id')::uuid);
  end loop;
  for i in 2..4 loop
    execute 'reset role';
    person := ('d9000000-0000-4000-8000-' || lpad(i::text,12,'0'))::uuid;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',person,'email','amount-' || i || '@example.com')::text,true);
    set local role authenticated;
    perform public.redeem_invitation(null,case when i=2 then parent_id else invite_ids[i-2] end);
  end loop;
  execute 'reset role';
  if not exists(select 1 from public.chitti_members m where m.chitti_id=second_chitti and user_id='d9000000-0000-4000-8000-000000000002' and contribution_amount_paise=666666) then raise exception 'Exact thirds remainder failed'; end if;
  if (select sum(contribution_amount_paise) from public.chitti_members m where m.chitti_id=second_chitti and payout_position=2)<>2000000 then raise exception 'Thirds do not sum to full amount'; end if;
  -- Active splits recheck payment state at acceptance, not only invitation creation.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email','amount-admin@example.com')::text,true);
  set local role authenticated;
  result := public.add_coowner_amount_invitation(second_chitti,'d9000000-0000-4000-8000-000000000002',500000,'Extra owner','amount-8@example.com','9000000000');
  parent_id := (result->>'invitation_id')::uuid;
  execute 'reset role';
  update public.contributions x set status='submitted' from public.rounds r
  where x.round_id=r.id and r.chitti_id=second_chitti and x.member_id='d9000000-0000-4000-8000-000000000002';
  perform set_config('request.jwt.claims','{"sub":"d9000000-0000-4000-8000-000000000008","email":"amount-8@example.com"}',true);
  set local role authenticated;
  begin
    perform public.redeem_invitation(null,parent_id);
    raise exception 'TEST: submitted payment was split';
  exception when others then if sqlerrm not like 'This owner has submitted or confirmed payments%' then raise; end if; end;
  execute 'reset role';
  update public.contributions x set status='due' from public.rounds r
  where x.round_id=r.id and r.chitti_id=second_chitti and x.member_id='d9000000-0000-4000-8000-000000000002';
  set local role authenticated;
  perform public.redeem_invitation(null,parent_id);
  execute 'reset role';
  if not exists(select 1 from public.chitti_members m where m.chitti_id=second_chitti and user_id='d9000000-0000-4000-8000-000000000002' and contribution_amount_paise=166666)
    or not exists(select 1 from public.chitti_members m where m.chitti_id=second_chitti and user_id='d9000000-0000-4000-8000-000000000008' and contribution_amount_paise=500000) then raise exception 'Active exact amount split failed'; end if;
  if exists(select 1 from public.rounds r join public.contributions x on x.round_id=r.id where r.chitti_id=second_chitti group by r.id having sum(x.amount_paise)<>4000000) then raise exception 'Active split changed round total'; end if;
  raise notice 'Unlimited amount-based co-owners, exact paise, thirds, reservations and separate payouts passed';
end;
$$;
rollback;
