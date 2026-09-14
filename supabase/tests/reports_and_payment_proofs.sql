begin;

do $$
declare
  v_admin constant uuid := '81111111-1111-4111-8111-111111111111';
  v_member constant uuid := '82222222-2222-4222-8222-222222222222';
  v_chitti constant uuid := '83333333-3333-4333-8333-333333333333';
  v_pending_chitti constant uuid := '83333333-3333-4333-8333-333333333334';
  v_round constant uuid := '84444444-4444-4444-8444-444444444444';
  v_contribution uuid;
  v_reports jsonb;
  v_member_report jsonb;
  v_snapshot jsonb;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  insert into auth.users(
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values
    (v_admin, 'authenticated', 'authenticated', 'report-test-admin@example.com', now(), '{}', '{"full_name":"Report admin"}', now(), now()),
    (v_member, 'authenticated', 'authenticated', 'report-test-member@example.com', now(), '{}', '{"full_name":"Report member"}', now(), now());
  update public.app_roles set role = 'admin' where user_id = v_admin;

  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, start_date,
    first_due_date, due_day, upi_id, payee_name, status, locked_at
  ) values (
    v_chitti, 'Report test', v_admin, 500000, 2, v_today - 2, v_today - 1,
    extract(day from v_today - 1), 'admin@test', 'Report admin', 'active', now()
  );
  insert into public.chittis(
    id, name, admin_id, monthly_amount_paise, member_count, start_date,
    first_due_date, due_day, upi_id, payee_name, status
  ) values (
    v_pending_chitti, 'Pending invitation test', v_admin, 300000, 2, v_today,
    v_today + 1, extract(day from v_today + 1), 'admin@test', 'Report admin', 'inviting'
  );
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position) values
    (v_chitti, v_admin, true, 1),
    (v_chitti, v_member, false, 2);
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position)
  values (v_pending_chitti, v_admin, true, 1);
  insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash, status, accepted_by, accepted_at)
  values (v_chitti, 'Earlier invited member', 'report-test-member@example.com', '+91 90000 00000', extensions.digest('saved-contact-test', 'sha256'), 'accepted', v_member, now());
  insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash)
  values (v_pending_chitti, 'Report member', 'report-test-member@example.com', '+91 90000 00000', extensions.digest('dashboard-invite-test', 'sha256'));
  insert into public.rounds(id, chitti_id, round_number, due_date, recipient_id, status)
  values (v_round, v_chitti, 1, v_today - 1, v_admin, 'collecting');
  insert into public.payouts(round_id) values (v_round);
  insert into public.contributions(round_id, member_id, status, method, submitted_at, confirmed_at, confirmed_on_time) values
    (v_round, v_admin, 'confirmed', 'cash', now() - interval '2 days', now() - interval '2 days', true),
    (v_round, v_member, 'overdue', null, null, null, null);
  select id into v_contribution from public.contributions where round_id = v_round and member_id = v_member;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'email', 'report-test-admin@example.com')::text, true);
  set local role authenticated;
  select public.get_reports() into v_reports;
  if jsonb_array_length(v_reports) <> 2 then
    raise exception 'Administrator report did not contain both managed members';
  end if;
  if jsonb_array_length(public.get_admin_contacts()) <> 1
     or public.get_admin_contacts()->0->>'email' <> 'report-test-member@example.com' then
    raise exception 'Administrator saved contact was not returned';
  end if;
  select value into v_member_report from jsonb_array_elements(v_reports) where value->>'userId' = v_member::text;
  if (v_member_report->>'missedDueDates')::int <> 1 or (v_member_report->>'reliabilityScore')::numeric <> 0 then
    raise exception 'Administrator reliability totals were incorrect: %', v_member_report;
  end if;

  execute 'reset role';
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_member, 'email', 'report-test-member@example.com')::text, true);
  set local role authenticated;
  select public.get_reports() into v_reports;
  if jsonb_array_length(v_reports) <> 1 or v_reports->0->>'userId' <> v_member::text then
    raise exception 'Member report exposed another user';
  end if;
  if public.get_admin_contacts() <> '[]'::jsonb then
    raise exception 'A member could read administrator saved contacts';
  end if;
  select public.get_app_snapshot() into v_snapshot;
  if jsonb_array_length(v_snapshot->'pendingInvitations') <> 1
     or v_snapshot->'pendingInvitations'->0->>'chittiName' <> 'Pending invitation test' then
    raise exception 'Pending invitation was not returned on the member dashboard: %', v_snapshot->'pendingInvitations';
  end if;
  if (v_snapshot->'pendingInvitations'->0) ?| array['token', 'tokenHash', 'invitedEmail', 'invitedPhone'] then
    raise exception 'Pending invitation exposed private invitation data';
  end if;

  perform public.submit_contribution(
    v_round,
    'upi',
    'REPORT-PROOF',
    v_member::text || '/' || v_contribution::text || '/proof.jpg'
  );
  if not exists (
    select 1 from public.contributions
    where id = v_contribution
      and status = 'submitted'
      and proof_path = v_member::text || '/' || v_contribution::text || '/proof.jpg'
  ) then
    raise exception 'Payment proof path was not recorded';
  end if;

  begin
    perform public.submit_contribution(v_round, 'upi', null, v_admin::text || '/' || v_contribution::text || '/wrong.jpg');
    raise exception 'A member could attach a proof under another user path';
  exception when others then
    if sqlerrm = 'A member could attach a proof under another user path' then raise; end if;
  end;

  raise notice 'Report privacy, reliability score, and payment proof tests passed';
end;
$$;

rollback;
