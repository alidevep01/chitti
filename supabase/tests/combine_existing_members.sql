begin;
do $$
declare
  admin_id uuid := 'e9111111-1111-4111-8111-111111111111';
  keep_id uuid := 'e9222222-2222-4222-8222-222222222222';
  move_id uuid := 'e9333333-3333-4333-8333-333333333333';
  tail_id uuid := 'e9444444-4444-4444-8444-444444444444';
  person uuid; cid uuid; ki uuid; mi uuid; kk text; mk text; kid uuid; mid uuid;
  amount bigint; n int; scenario int;
begin
  foreach person in array array[admin_id,keep_id,move_id,tail_id] loop
    insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    values(person,'authenticated','authenticated',person::text || '@combine.test',now(),'{}','{"full_name":"Combine test"}',now(),now());
  end loop;
  update public.app_roles set role = 'admin' where user_id = admin_id;
  for scenario in 1..4 loop
    cid := gen_random_uuid(); ki := gen_random_uuid(); mi := gen_random_uuid();
    kk := case when scenario in (3,4) then 'invitation' else 'member' end;
    mk := case when scenario in (2,4) then 'invitation' else 'member' end;
    kid := case when kk = 'member' then keep_id else ki end;
    mid := case when mk = 'member' then move_id else mi end;
    insert into public.chittis(id,name,admin_id,monthly_amount_paise,member_count,start_date,first_due_date,due_day,upi_id,payee_name,status,is_imported,imported_completed_months)
    values(cid,'Combine regression',admin_id,2000000,4,'2026-01-01','2026-01-31',31,'admin@test','Admin','inviting',true,0);
    insert into public.chitti_members(chitti_id,user_id,is_admin,payout_position)
    values(cid,admin_id,true,1),(cid,tail_id,false,4);
    if kk = 'member' then insert into public.chitti_members(chitti_id,user_id,payout_position) values(cid,keep_id,2); end if;
    if mk = 'member' then insert into public.chitti_members(chitti_id,user_id,payout_position) values(cid,move_id,3); end if;
    -- Include accepted metadata to test the unique main-invitation index when merging joined members.
    insert into public.invitations(id,chitti_id,invited_name,invited_email,invited_phone,token_hash,status,accepted_by,payout_position)
    values(ki,cid,'Keep',keep_id::text || '@combine.test','9000000000',extensions.digest(ki::text,'sha256'),
      case when kk = 'member' then 'accepted'::public.invitation_status else 'pending'::public.invitation_status end,case when kk = 'member' then keep_id end,2),
      (mi,cid,'Move',move_id::text || '@combine.test','9000000000',extensions.digest(mi::text,'sha256'),
      case when mk = 'member' then 'accepted'::public.invitation_status else 'pending'::public.invitation_status end,case when mk = 'member' then move_id end,3);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',move_id,'email',move_id::text || '@combine.test')::text,true);
    set local role authenticated;
    begin
      perform public.combine_existing_members(cid,kk,kid,mk,mid,500000,4,2,3);
      raise exception 'TEST: non-admin was allowed';
    exception when raise_exception then if sqlerrm <> 'Administrator access required' then raise; end if; end;
    reset role;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email',admin_id::text || '@combine.test')::text,true);
    set local role authenticated;
    foreach amount in array array[0::bigint,2000000::bigint] loop
      begin
        perform public.combine_existing_members(cid,kk,kid,mk,mid,amount,4,2,3);
        raise exception 'TEST: invalid amount was allowed';
      exception when raise_exception then if sqlerrm <> 'Enter an amount below the selected owner''s available amount, leaving at least one paise' then raise; end if; end;
    end loop;
    begin
      perform public.combine_existing_members(cid,kk,kid,mk,mid,500000,5,2,3);
      raise exception 'TEST: stale roster was allowed';
    exception when raise_exception then if sqlerrm <> 'The roster changed. Close and reopen Combine existing members' then raise; end if; end;
    perform public.combine_existing_members(cid,kk,kid,mk,mid,500000,4,2,3);
    reset role;
    if not exists(select 1 from public.chittis where id = cid and member_count = 3 and end_date = '2026-03-31') then raise exception 'Schedule was not shortened'; end if;
    if not exists(select 1 from public.chitti_members where chitti_id = cid and user_id = tail_id and payout_position = 3) then raise exception 'Tail rank was not compacted'; end if;
    -- Accept child before parent to exercise both pending-invitation orders.
    if mk = 'invitation' then
      perform set_config('request.jwt.claims',jsonb_build_object('sub',move_id,'email',move_id::text || '@combine.test')::text,true);
      set local role authenticated;
      perform public.redeem_invitation(null,mi);
      reset role;
    end if;
    if kk = 'invitation' then
      perform set_config('request.jwt.claims',jsonb_build_object('sub',keep_id,'email',keep_id::text || '@combine.test')::text,true);
      set local role authenticated;
      perform public.redeem_invitation(null,ki);
      reset role;
    end if;
    perform public.activate_imported_chitti(cid);
    if not exists(select 1 from public.chitti_members where chitti_id = cid and user_id = keep_id and payout_position = 2 and contribution_amount_paise = 1500000)
      or not exists(select 1 from public.chitti_members where chitti_id = cid and user_id = move_id and payout_position = 2 and contribution_amount_paise = 500000) then raise exception 'Wrong shared amounts'; end if;
    select count(*) into n from public.rounds where chitti_id = cid;
    if n <> 3 then raise exception 'Expected three rounds, got %',n; end if;
    if (select count(*) from public.round_payout_shares s join public.rounds r on r.id=s.round_id where r.chitti_id=cid and r.round_number=2) <> 2 then raise exception 'Separate payouts missing'; end if;
    if (select sum(s.amount_paise) from public.round_payout_shares s join public.rounds r on r.id=s.round_id where r.chitti_id=cid and r.round_number=2) <> 6000000 then raise exception 'Wrong payout pot'; end if;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email',admin_id::text || '@combine.test')::text,true);
    set local role authenticated;
    begin
      perform public.combine_existing_members(cid,'member',admin_id,'member',tail_id,500000,3,1,3);
      raise exception 'TEST: active chitti merge allowed';
    exception when raise_exception then if sqlerrm <> 'Combine only in a pending existing chitti with no completed months or payment history' then raise; end if; end;
    reset role;
  end loop;
  raise notice 'Combine members: all four joined/invited combinations, permissions, amounts, stale roster, activation and separate payouts passed';
end;
$$;
rollback;
