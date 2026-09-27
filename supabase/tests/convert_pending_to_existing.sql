begin;

do $$
declare
  v_admin constant uuid := '81111111-1111-4111-8111-111111111111';
  v_member constant uuid := '82222222-2222-4222-8222-222222222222';
  v_invitee constant uuid := '83333333-3333-4333-8333-333333333333';
  v_chitti constant uuid := '84444444-4444-4444-8444-444444444444';
  v_invitation constant uuid := '85555555-5555-4555-8555-555555555555';
  v_run constant uuid := '86666666-6666-4666-8666-666666666666';
  v_token constant text := 'convert-existing-test-token';
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values
    (v_admin, 'authenticated', 'authenticated', 'convert-admin@example.com', now(), '{}', '{"full_name":"Convert admin"}', now(), now()),
    (v_member, 'authenticated', 'authenticated', 'convert-member@example.com', now(), '{}', '{"full_name":"Joined member"}', now(), now()),
    (v_invitee, 'authenticated', 'authenticated', 'convert-invitee@example.com', now(), '{}', '{"full_name":"Invited member"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = v_admin;

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, start_date,
    first_due_date, due_day, upi_id, payee_name, status, shuffle_scheduled_at
  ) values (
    v_chitti, 'Converted existing chitti', v_admin, 500000, 3,
    (current_date - interval '1 month')::date,
    (current_date - interval '1 month')::date,
    extract(day from current_date), 'admin@test', 'Convert admin', 'awaiting_approval', now()
  );
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position) values
    (v_chitti, v_admin, true, 1),
    (v_chitti, v_member, false, 2);
  insert into public.invitations(id, chitti_id, invited_name, invited_email, invited_phone, token_hash)
  values (
    v_invitation, v_chitti, 'Invited member', 'convert-invitee@example.com', '9000000000',
    extensions.digest(v_token, 'sha256')
  );
  insert into public.shuffle_runs(id, chitti_id, run_number, idempotency_key, status, result_hash, started_by)
  values (v_run, v_chitti, 1, '87777777-7777-4777-8777-777777777777', 'revealed', repeat('a', 64), v_admin);
  insert into public.shuffle_assignments(shuffle_run_id, member_id, payout_position) values
    (v_run, v_admin, 1),
    (v_run, v_member, 2);
  insert into public.shuffle_approvals(shuffle_run_id, member_id, status) values
    (v_run, v_admin, 'accepted'),
    (v_run, v_member, 'pending');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'convert-admin@example.com')::text, true);
  set local role authenticated;
  perform public.convert_pending_chitti_to_existing(
    v_chitti,
    1::smallint,
    jsonb_build_array(
      jsonb_build_object('kind', 'invitation', 'id', v_invitation),
      jsonb_build_object('kind', 'member', 'id', v_member)
    )
  );
  execute 'reset role';

  if not exists(
    select 1 from public.chittis
    where id = v_chitti and is_imported and imported_completed_months = 1 and status = 'inviting'
  ) then
    raise exception 'Pending chitti was not converted to imported/inviting state';
  end if;
  if (select payout_position from public.invitations where id = v_invitation) <> 2
     or (select payout_position from public.chitti_members where chitti_id = v_chitti and user_id = v_member) <> 3 then
    raise exception 'Manual drag order was not saved';
  end if;
  if exists(select 1 from public.shuffle_runs where chitti_id = v_chitti) then
    raise exception 'Old random shuffle data was not removed';
  end if;
  if exists(select 1 from public.rounds where chitti_id = v_chitti) then
    raise exception 'Converted chitti activated before the pending invitation was accepted';
  end if;

  -- A member must not be able to edit even while the import is pending.
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_member)::text, true);
  set local role authenticated;
  begin
    perform public.convert_pending_chitti_to_existing(v_chitti, 1::smallint, '[]'::jsonb);
    raise exception 'TEST: member edit was allowed';
  exception when others then
    if sqlerrm <> 'Administrator access required' then raise; end if;
  end;
  execute 'reset role';

  -- Include the accepted invitation's old position to exercise unique-index collisions.
  insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash, status, accepted_by, payout_position)
  values (v_chitti, 'Joined member', 'convert-member@example.com', '9000000000', extensions.digest('accepted-ranking-test', 'sha256'), 'accepted', v_member, 3);

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin)::text, true);
  set local role authenticated;
  begin
    perform public.convert_pending_chitti_to_existing(v_chitti, 1::smallint, null);
    raise exception 'TEST: null order accepted';
  exception when others then
    if sqlerrm <> 'Payout order must be an array' then raise; end if;
  end;
  begin
    perform public.convert_pending_chitti_to_existing(v_chitti, 1::smallint, jsonb_build_array(
      jsonb_build_object('kind', 'member', 'id', v_member),
      jsonb_build_object('kind', 'member', 'id', v_member)));
    raise exception 'TEST: duplicate order accepted';
  exception when others then
    if sqlerrm <> 'A payout-order item was repeated' then raise; end if;
  end;
  begin
    perform public.convert_pending_chitti_to_existing(v_chitti, 0::smallint, '[]'::jsonb);
    raise exception 'TEST: historical month count changed';
  exception when others then
    if sqlerrm <> 'Editing the ranking cannot change the imported completed months' then raise; end if;
  end;
  perform public.convert_pending_chitti_to_existing(v_chitti, 1::smallint, jsonb_build_array(
    jsonb_build_object('kind', 'member', 'id', v_member),
    jsonb_build_object('kind', 'invitation', 'id', v_invitation)));
  execute 'reset role';
  if (select payout_position from public.chitti_members where chitti_id = v_chitti and user_id = v_member) <> 2
     or (select payout_position from public.invitations where chitti_id = v_chitti and accepted_by = v_member) <> 2
     or (select payout_position from public.invitations where id = v_invitation) <> 3 then
    raise exception 'Pending import ranking or accepted invitation was not updated';
  end if;
  if not exists(select 1 from public.notifications where user_id = v_member and kind = 'chitti.ranking_updated')
     or not exists(select 1 from public.audit_events where chitti_id = v_chitti and action = 'chitti.ranking_updated') then
    raise exception 'Ranking change must notify and be audited';
  end if;

  -- Unassigned months must not be compacted when editing a partially filled import.
  update public.chittis set member_count = 5 where id = v_chitti;
  update public.invitations set payout_position = 5 where id = v_invitation;
  set local role authenticated;
  perform public.convert_pending_chitti_to_existing(v_chitti, 1::smallint, jsonb_build_array(
    jsonb_build_object('kind', 'invitation', 'id', v_invitation),
    jsonb_build_object('kind', 'member', 'id', v_member)));
  execute 'reset role';
  if (select payout_position from public.chitti_members where chitti_id = v_chitti and user_id = v_member) <> 5
     or (select payout_position from public.chitti_members where chitti_id = v_chitti and user_id = v_admin) <> 1 then
    raise exception 'Unassigned months or admin position were changed';
  end if;
  -- Restore the three-slot fixture for final invitation activation checks.
  update public.chitti_members set payout_position = 3 where chitti_id = v_chitti and user_id = v_member;
  update public.invitations set payout_position = 3 where chitti_id = v_chitti and accepted_by = v_member;
  update public.chittis set member_count = 3 where id = v_chitti;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_invitee, 'email', 'convert-invitee@example.com')::text, true);
  set local role authenticated;
  perform public.redeem_invitation(v_token, null);
  set constraints invitations_activate_imported_chitti immediate;
  execute 'reset role';

  if not exists(select 1 from public.chittis where id = v_chitti and status = 'active' and locked_at is not null) then
    raise exception 'Converted chitti did not activate when the final member joined';
  end if;
  if not exists(select 1 from public.rounds where chitti_id = v_chitti and round_number = 2 and recipient_id = v_invitee)
     or not exists(select 1 from public.rounds where chitti_id = v_chitti and round_number = 3 and recipient_id = v_member) then
    raise exception 'Activated rounds did not preserve the manual payout ranking';
  end if;
  if not exists(
    select 1 from public.round_payout_shares share
    join public.rounds round_item on round_item.id = share.round_id
    where round_item.chitti_id = v_chitti and round_item.round_number = 1 and share.status = 'paid'
  ) then
    raise exception 'Historical payout share was not marked paid';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin)::text, true);
  set local role authenticated;
  begin
    perform public.convert_pending_chitti_to_existing(v_chitti, 1::smallint, '[]'::jsonb);
    raise exception 'TEST: active ranking rewritten';
  exception when others then
    if sqlerrm <> 'Only a pending chitti can be changed to an existing chitti' then raise; end if;
  end;
  execute 'reset role';
  raise notice 'Pending-to-existing conversion, repeat ranking edits, privacy and locking tests passed';
end;
$$;

rollback;
