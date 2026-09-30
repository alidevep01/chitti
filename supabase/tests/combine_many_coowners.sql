begin;
do $$
declare
  users uuid[] := '{}'; invites uuid[] := '{}'; cid uuid := gen_random_uuid(); person uuid; invitation uuid;
  amount bigint; count_before integer; move_kind text; move_id uuid; destination integer;
begin
  for i in 1..8 loop
    person := gen_random_uuid(); users := array_append(users, person);
    insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    values(person,'authenticated','authenticated',person::text || '@many.test',now(),'{}','{"full_name":"Many owners"}',now(),now());
  end loop;
  update public.app_roles set role = 'admin' where user_id = users[1];
  insert into public.chittis(id,name,admin_id,monthly_amount_paise,member_count,start_date,first_due_date,due_day,upi_id,payee_name,status,is_imported,imported_completed_months)
  values(cid,'Six shared owners',users[1],2000000,8,'2026-01-01','2026-01-01',1,'admin@test','Admin','inviting',true,0);
  insert into public.chitti_members(chitti_id,user_id,is_admin,payout_position) values(cid,users[1],true,1);
  for i in 2..8 loop
    invitation := gen_random_uuid(); invites := array_append(invites,invitation);
    if i in (3,5,7) then insert into public.chitti_members(chitti_id,user_id,payout_position) values(cid,users[i],i); end if;
    insert into public.invitations(id,chitti_id,invited_name,invited_email,invited_phone,token_hash,status,accepted_by,payout_position)
    values(invitation,cid,'Owner ' || i,users[i]::text || '@many.test','9000000000',extensions.digest(invitation::text,'sha256'),
      case when i in (3,5,7) then 'accepted'::public.invitation_status else 'pending'::public.invitation_status end,
      case when i in (3,5,7) then users[i] end,i);
  end loop;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'email',users[1]::text || '@many.test')::text,true);
  for i in 3..7 loop
    count_before := 11-i; -- 8,7,6,5,4 positions before successive combines.
    move_kind := case when i in (3,5,7) then 'member' else 'invitation' end;
    move_id := case when move_kind = 'member' then users[i] else invites[i-1] end;
    set local role authenticated;
    perform public.combine_existing_members(cid,'invitation',invites[1],move_kind,move_id,300001,count_before,2,3);
    reset role;
  end loop;
  if (select member_count from public.chittis where id = cid) <> 3 then raise exception 'Wrong shortened duration'; end if;
  select sum(coowner_amount_paise) into amount from public.invitations where chitti_id = cid and coowner_source_invitation_id = invites[1] and status in ('pending','accepted');
  if amount <> 1500005 then raise exception 'Reservations must include all five co-owners'; end if;
  -- Existing group members cannot be removed as if they were full positions.
  set local role authenticated;
  begin
    perform public.combine_existing_members(cid,'member',users[1],'member',users[3],1,3,1,2);
    raise exception 'TEST: partial position was allowed to move';
  exception when raise_exception then if sqlerrm <> 'The moving person must have a separate full position with no reserved shares' then raise; end if; end;
  -- Overspending is rejected even though the original main amount is still 20,000.
  begin
    perform public.combine_existing_members(cid,'invitation',invites[1],'invitation',invites[7],499995,3,2,3);
    raise exception 'TEST: reserved funds were overspent';
  exception when raise_exception then if sqlerrm <> 'Enter an amount below the selected owner''s available amount, leaving at least one paise' then raise; end if; end;
  reset role;
  -- Main owner accepts before two pending children; accepted children must not be deducted twice.
  foreach destination in array array[2,4,6,8] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',users[destination],'email',users[destination]::text || '@many.test')::text,true);
    set local role authenticated;
    perform public.redeem_invitation(null,invites[destination-1]);
    reset role;
  end loop;
  perform public.activate_imported_chitti(cid);
  if (select contribution_amount_paise from public.chitti_members where chitti_id=cid and user_id=users[2]) <> 499995 then raise exception 'Wrong remaining main amount'; end if;
  if (select count(*) from public.chitti_members where chitti_id=cid and payout_position=2) <> 6 then raise exception 'Six owners must share one position'; end if;
  if (select sum(contribution_amount_paise) from public.chitti_members where chitti_id=cid and payout_position=2) <> 2000000 then raise exception 'Shared amounts do not total one full position'; end if;
  if (select count(*) from public.round_payout_shares s join public.rounds r on r.id=s.round_id where r.chitti_id=cid and r.round_number=2) <> 6 then raise exception 'Six independent payouts required'; end if;
  if (select sum(s.amount_paise) from public.round_payout_shares s join public.rounds r on r.id=s.round_id where r.chitti_id=cid and r.round_number=2) <> 6000000 then raise exception 'Wrong combined payout total'; end if;
  -- A joined main owner can also absorb five joined full positions. These members
  -- deliberately lack invitation metadata, exercising the accepted-record fallback.
  cid := gen_random_uuid();
  insert into public.chittis(id,name,admin_id,monthly_amount_paise,member_count,start_date,first_due_date,due_day,upi_id,payee_name,status,is_imported,imported_completed_months)
  values(cid,'Six joined owners',users[1],2000000,8,'2026-01-01','2026-01-01',1,'admin@test','Admin','inviting',true,0);
  for i in 1..7 loop
    insert into public.chitti_members(chitti_id,user_id,is_admin,payout_position) values(cid,users[i],i=1,i);
  end loop;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',users[1],'email',users[1]::text || '@many.test')::text,true);
  set local role authenticated;
  for i in 3..7 loop
    perform public.combine_existing_members(cid,'member',users[2],'member',users[i],333333,11-i,2,3);
  end loop;
  reset role;
  if (select contribution_amount_paise from public.chitti_members where chitti_id=cid and user_id=users[2]) <> 333335 then raise exception 'Wrong remaining joined-owner amount'; end if;
  if (select count(*) from public.chitti_members where chitti_id=cid and payout_position=2 and contribution_amount_paise=333333) <> 5 then raise exception 'Earlier co-owner amounts changed'; end if;
  if (select sum(contribution_amount_paise) from public.chitti_members where chitti_id=cid and payout_position=2) <> 2000000 then raise exception 'Joined group must total exactly one slot'; end if;
  raise notice 'Unlimited combining: six mixed and six joined owners, reservations, redemption and independent payouts passed';
end;
$$;
rollback;
