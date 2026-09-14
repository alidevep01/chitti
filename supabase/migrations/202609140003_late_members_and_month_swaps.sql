begin;

alter table public.chittis drop constraint chittis_member_count_check;
alter table public.chittis add constraint chittis_member_count_check check (member_count between 2 and 50);
alter table public.invitations add column late_join boolean not null default false;

create type public.payout_adjustment_status as enum ('awaiting_contribution', 'ready', 'paid');

create table public.payout_adjustments (
  id uuid primary key default gen_random_uuid(),
  chitti_id uuid not null references public.chittis(id) on delete restrict,
  round_id uuid not null references public.rounds(id) on delete restrict,
  contribution_id uuid not null references public.contributions(id) on delete restrict,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  source_member_id uuid not null references public.profiles(id) on delete restrict,
  amount_paise bigint not null check (amount_paise > 0),
  status public.payout_adjustment_status not null default 'awaiting_contribution',
  reference text check (char_length(reference) <= 100),
  confirmed_by uuid references public.profiles(id) on delete restrict,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (round_id, source_member_id)
);
create index payout_adjustments_chitti_status_idx on public.payout_adjustments(chitti_id, status);
create trigger payout_adjustments_touch before update on public.payout_adjustments for each row execute function public.touch_updated_at();
alter table public.payout_adjustments enable row level security;
create policy payout_adjustments_affected_select on public.payout_adjustments for select to authenticated
using (public.is_chitti_admin(chitti_id) or recipient_id = auth.uid() or source_member_id = auth.uid());
grant select on public.payout_adjustments to authenticated;

create function public.add_chitti_member_invitation(p_chitti_id uuid, p_name text, p_email text, p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_invitation_id uuid;
  v_token text;
  v_late boolean;
begin
  select * into v_chitti from public.chittis where id = p_chitti_id for update;
  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if v_chitti.status not in ('inviting', 'ready', 'active') then
    raise exception 'Add members before scheduling a shuffle or after the chitti becomes active';
  end if;
  if v_chitti.member_count >= 50 then raise exception 'A chitti can have at most 50 members'; end if;
  if char_length(btrim(p_name)) not between 2 and 80 then raise exception 'Enter a valid member name'; end if;
  if position('@' in p_email) < 2 then raise exception 'Enter a valid email address'; end if;
  if char_length(btrim(p_phone)) < 8 then raise exception 'Enter a valid phone number'; end if;
  if exists(
    select 1 from public.chitti_members cm join public.profiles p on p.id = cm.user_id
    where cm.chitti_id = p_chitti_id and lower(p.email) = lower(btrim(p_email))
  ) or exists(
    select 1 from public.invitations i
    where i.chitti_id = p_chitti_id and lower(i.invited_email) = lower(btrim(p_email)) and i.status = 'pending'
  ) then raise exception 'This email is already a member or has a pending invitation'; end if;

  v_late := v_chitti.status = 'active';
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash, late_join)
  values (p_chitti_id, btrim(p_name), lower(btrim(p_email)), btrim(p_phone), extensions.digest(v_token, 'sha256'), v_late)
  returning id into v_invitation_id;

  if not v_late then
    update public.chittis set member_count = member_count + 1, status = 'inviting' where id = p_chitti_id;
  end if;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select id, 'invitation.created', 'You have a private Chitti invitation',
    'Open Chitti to review your invitation.', '/invite?invitation=' || v_invitation_id,
    'invite:' || v_invitation_id
  from public.profiles where lower(email) = lower(btrim(p_email))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), p_chitti_id, 'invitation.added', 'invitation', v_invitation_id::text,
    jsonb_build_object('late_join', v_late, 'invited_email', lower(btrim(p_email))));
  return jsonb_build_object('invitation_id', v_invitation_id, 'token', v_token, 'late_join', v_late);
end;
$$;

create or replace function public.redeem_invitation(p_token text default null, p_invitation_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.invitations;
  v_chitti public.chittis;
  v_email text;
  v_joined int;
  v_new_position int;
  v_new_round_id uuid;
  v_contribution record;
  v_elapsed_count int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_email := lower(coalesce(auth.jwt()->>'email', ''));
  select * into v_invite from public.invitations
  where (p_token is not null and token_hash = extensions.digest(p_token, 'sha256'))
     or (p_invitation_id is not null and id = p_invitation_id)
  for update;
  if v_invite.id is null or v_invite.status <> 'pending' or v_invite.expires_at < now() then
    raise exception 'Invitation is invalid or expired';
  end if;
  if lower(v_invite.invited_email) <> v_email then raise exception 'Sign in with the invited Google email'; end if;
  select * into v_chitti from public.chittis where id = v_invite.chitti_id for update;
  if v_invite.late_join and v_chitti.status <> 'active' then
    raise exception 'This late-join invitation is no longer available';
  end if;

  update public.profiles set phone = case when btrim(phone) = '' then v_invite.invited_phone else phone end where id = auth.uid();

  if v_invite.late_join then
    v_new_position := v_chitti.member_count + 1;
    insert into public.chitti_members(chitti_id, user_id, payout_position)
    values (v_invite.chitti_id, auth.uid(), v_new_position);
    update public.chittis set member_count = v_new_position where id = v_invite.chitti_id;

    insert into public.contributions(round_id, member_id, status)
    select r.id, auth.uid(),
      case when r.status = 'completed' or r.due_date < (now() at time zone 'Asia/Kolkata')::date
        then 'overdue'::public.contribution_status else 'due'::public.contribution_status end
    from public.rounds r where r.chitti_id = v_invite.chitti_id;

    for v_contribution in
      select c.id contribution_id, r.id round_id, r.recipient_id
      from public.rounds r join public.contributions c on c.round_id = r.id and c.member_id = auth.uid()
      where r.chitti_id = v_invite.chitti_id and r.status = 'completed'
    loop
      insert into public.payout_adjustments(chitti_id, round_id, contribution_id, recipient_id, source_member_id, amount_paise)
      values (v_invite.chitti_id, v_contribution.round_id, v_contribution.contribution_id,
        v_contribution.recipient_id, auth.uid(), v_chitti.monthly_amount_paise);
    end loop;

    update public.rounds set status = 'collecting'
    where chitti_id = v_invite.chitti_id and status = 'ready_for_payout';
    update public.payouts p set status = 'blocked'
    from public.rounds r where r.id = p.round_id and r.chitti_id = v_invite.chitti_id and r.status = 'collecting' and p.status = 'ready';

    insert into public.rounds(chitti_id, round_number, due_date, recipient_id, status)
    values (v_invite.chitti_id, v_new_position,
      (v_chitti.first_due_date + make_interval(months => v_new_position - 1))::date,
      auth.uid(), 'upcoming') returning id into v_new_round_id;
    insert into public.contributions(round_id, member_id)
    select v_new_round_id, user_id from public.chitti_members where chitti_id = v_invite.chitti_id;
    insert into public.payouts(round_id) values (v_new_round_id);

    select count(*) into v_elapsed_count from public.rounds
    where chitti_id = v_invite.chitti_id and round_number < v_new_position
      and (status in ('collecting', 'ready_for_payout', 'completed') or due_date <= (now() at time zone 'Asia/Kolkata')::date);
    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    values (auth.uid(), 'member.catchup_required', 'Catch-up contributions required',
      'You joined after the chitti began. Review and submit ' || v_elapsed_count || ' elapsed contribution(s).',
      '/chitti/' || v_invite.chitti_id, 'catchup:' || v_invite.id);
    perform public.notify_chitti_members(v_invite.chitti_id, 'member.late_joined', 'A member joined the active chitti',
      'The monthly pot and remaining schedule have been updated.', '/chitti/' || v_invite.chitti_id,
      v_invite.id::text, auth.uid());
  else
    insert into public.chitti_members(chitti_id, user_id) values (v_invite.chitti_id, auth.uid());
    select count(*) into v_joined from public.chitti_members where chitti_id = v_invite.chitti_id;
    update public.chittis set status = case when v_joined = member_count
      then 'ready'::public.chitti_status else 'inviting'::public.chitti_status end
    where id = v_invite.chitti_id;
  end if;

  update public.invitations set status = 'accepted', accepted_by = auth.uid(), accepted_at = now() where id = v_invite.id;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select admin_id, 'invitation.accepted', v_invite.invited_name || ' joined',
    'A member accepted the invitation.', '/chitti/' || v_invite.chitti_id, 'joined:' || v_invite.id
  from public.chittis where id = v_invite.chitti_id;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), v_invite.chitti_id, 'invitation.accepted', 'invitation', v_invite.id::text,
    jsonb_build_object('late_join', v_invite.late_join, 'new_position', v_new_position));
  return v_invite.chitti_id;
end;
$$;

create or replace function public.submit_contribution(p_round_id uuid, p_method public.payment_method, p_reference text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_round public.rounds; v_contribution_id uuid; v_catchup boolean;
begin
  select * into v_round from public.rounds where id = p_round_id;
  if v_round.id is null or not public.is_chitti_member(v_round.chitti_id) then raise exception 'This round is unavailable'; end if;
  select c.id, exists(select 1 from public.payout_adjustments pa where pa.contribution_id = c.id and pa.status = 'awaiting_contribution')
  into v_contribution_id, v_catchup from public.contributions c
  where c.round_id = p_round_id and c.member_id = auth.uid();
  if v_round.status <> 'collecting' and not coalesce(v_catchup, false) then raise exception 'This round is not open'; end if;
  update public.contributions set status = 'submitted', method = p_method, reference = nullif(p_reference,''),
    submitted_at = now(), confirmed_at = null, reviewed_by = null
  where id = v_contribution_id and status in ('due', 'rejected', 'overdue');
  if not found then raise exception 'Contribution cannot be submitted'; end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), v_round.chitti_id, 'contribution.submitted', 'contribution', v_contribution_id::text,
    jsonb_build_object('catchup', coalesce(v_catchup, false)));
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select admin_id, 'contribution.submitted', case when v_catchup then 'Catch-up payment awaiting review' else 'Payment awaiting review' end,
    'A member marked a contribution as paid.', '/chitti/' || v_round.chitti_id, 'submitted:' || v_contribution_id
  from public.chittis where id = v_round.chitti_id
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end; $$;

create or replace function public.review_contribution(p_contribution_id uuid, p_accepted boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_round public.rounds; v_chitti_id uuid; v_remaining int; v_adjustment public.payout_adjustments;
begin
  select r.* into v_round from public.contributions c join public.rounds r on r.id = c.round_id where c.id = p_contribution_id;
  v_chitti_id := v_round.chitti_id;
  if not public.is_chitti_admin(v_chitti_id) then raise exception 'Administrator access required'; end if;
  update public.contributions set status = case when p_accepted then 'confirmed'::public.contribution_status else 'rejected'::public.contribution_status end,
    reviewed_by = auth.uid(), confirmed_at = case when p_accepted then now() else null end
  where id = p_contribution_id and status = 'submitted';
  if not found then raise exception 'Contribution is not awaiting review'; end if;
  if p_accepted then
    update public.payout_adjustments set status = 'ready' where contribution_id = p_contribution_id and status = 'awaiting_contribution' returning * into v_adjustment;
    if v_adjustment.id is not null then
      insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
      values (v_adjustment.recipient_id, 'payout.topup_ready', 'An additional payout is ready',
        'A late member''s catch-up contribution was confirmed.', '/chitti/' || v_chitti_id, 'topup-ready:' || v_adjustment.id);
    end if;
    if v_round.status <> 'completed' then
      select count(*) into v_remaining from public.contributions where round_id = v_round.id and status <> 'confirmed';
      if v_remaining = 0 then
        update public.rounds set status = 'ready_for_payout' where id = v_round.id;
        update public.payouts set status = 'ready' where round_id = v_round.id;
      end if;
    end if;
  end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), v_chitti_id, 'contribution.reviewed', 'contribution', p_contribution_id::text, jsonb_build_object('accepted', p_accepted));
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select member_id, 'contribution.reviewed', case when p_accepted then 'Payment confirmed' else 'Payment needs attention' end,
    case when p_accepted then 'The administrator confirmed your contribution.' else 'The administrator could not confirm your contribution. Please review it.' end,
    '/chitti/' || v_chitti_id, 'reviewed:' || p_contribution_id || ':' || p_accepted
  from public.contributions where id = p_contribution_id
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end; $$;

create function public.confirm_payout_adjustment(p_adjustment_id uuid, p_reference text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_adjustment public.payout_adjustments;
begin
  select * into v_adjustment from public.payout_adjustments where id = p_adjustment_id for update;
  if v_adjustment.id is null or not public.is_chitti_admin(v_adjustment.chitti_id) then raise exception 'Administrator access required'; end if;
  update public.payout_adjustments set status = 'paid', reference = nullif(p_reference,''), confirmed_by = auth.uid(), paid_at = now()
  where id = p_adjustment_id and status = 'ready';
  if not found then raise exception 'This additional payout is not ready'; end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id)
  values (auth.uid(), v_adjustment.chitti_id, 'payout.topup_confirmed', 'payout_adjustment', p_adjustment_id::text);
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  values (v_adjustment.recipient_id, 'payout.topup_confirmed', 'Additional payout delivered',
    'The administrator recorded your late-member top-up as delivered.', '/chitti/' || v_adjustment.chitti_id,
    'topup-paid:' || p_adjustment_id);
end; $$;

create function public.swap_payout_months(p_chitti_id uuid, p_first_member_id uuid, p_second_member_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_chitti public.chittis; v_first public.chitti_members; v_second public.chitti_members; v_first_date date; v_second_date date;
begin
  if p_first_member_id = p_second_member_id then raise exception 'Choose two different members'; end if;
  select * into v_chitti from public.chittis where id = p_chitti_id for update;
  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then raise exception 'Administrator access required'; end if;
  if v_chitti.status <> 'active' then raise exception 'Payout months can be swapped only for an active chitti'; end if;
  select * into v_first from public.chitti_members where chitti_id = p_chitti_id and user_id = p_first_member_id;
  select * into v_second from public.chitti_members where chitti_id = p_chitti_id and user_id = p_second_member_id;
  if v_first.user_id is null or v_second.user_id is null then raise exception 'Both members must belong to this chitti'; end if;
  if v_first.is_admin or v_second.is_admin then raise exception 'The administrator must remain in payout month 1'; end if;
  if v_first.payout_position is null or v_second.payout_position is null then raise exception 'Both payout months must be assigned'; end if;
  if exists(
    select 1 from public.rounds r join public.payouts p on p.round_id = r.id
    where r.chitti_id = p_chitti_id and r.round_number in (v_first.payout_position, v_second.payout_position)
      and (r.status = 'completed' or p.status = 'paid')
  ) then raise exception 'Completed or paid payout months cannot be changed'; end if;

  update public.chitti_members set payout_position = case
    when user_id = p_first_member_id then v_second.payout_position
    when user_id = p_second_member_id then v_first.payout_position end
  where chitti_id = p_chitti_id and user_id in (p_first_member_id, p_second_member_id);
  update public.rounds set recipient_id = case
    when round_number = v_first.payout_position then p_second_member_id
    when round_number = v_second.payout_position then p_first_member_id end
  where chitti_id = p_chitti_id and round_number in (v_first.payout_position, v_second.payout_position);

  select due_date into v_first_date from public.rounds where chitti_id = p_chitti_id and round_number = v_second.payout_position;
  select due_date into v_second_date from public.rounds where chitti_id = p_chitti_id and round_number = v_first.payout_position;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key) values
    (p_first_member_id, 'payout.month_changed', 'Your payout month changed',
      'The administrator moved your payout to month ' || v_second.payout_position || ' (' || to_char(v_first_date, 'DD Mon YYYY') || ').',
      '/chitti/' || p_chitti_id, 'month-swap:' || p_chitti_id || ':' || p_first_member_id || ':' || now()),
    (p_second_member_id, 'payout.month_changed', 'Your payout month changed',
      'The administrator moved your payout to month ' || v_first.payout_position || ' (' || to_char(v_second_date, 'DD Mon YYYY') || ').',
      '/chitti/' || p_chitti_id, 'month-swap:' || p_chitti_id || ':' || p_second_member_id || ':' || now());
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), p_chitti_id, 'payout.months_swapped', 'chitti', p_chitti_id::text,
    jsonb_build_object('first_member', p_first_member_id, 'first_old_month', v_first.payout_position,
      'first_new_month', v_second.payout_position, 'second_member', p_second_member_id,
      'second_old_month', v_second.payout_position, 'second_new_month', v_first.payout_position));
end; $$;

create or replace function public.get_app_snapshot() returns jsonb language sql stable security definer set search_path = '' as $$
with me as (
  select p.*, coalesce(ar.role, 'member') role from public.profiles p left join public.app_roles ar on ar.user_id = p.id where p.id = auth.uid()
), my_chittis as (
  select c.* from public.chittis c join public.chitti_members cm on cm.chitti_id = c.id where cm.user_id = auth.uid() and c.archived_at is null
)
select jsonb_build_object(
  'userId', auth.uid(),
  'users', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', display_name, 'email', email, 'phone', phone, 'avatarUri', avatar_url, 'role', role)) from me), '[]'::jsonb),
  'chittis', coalesce((select jsonb_agg(jsonb_build_object(
    'id', c.id, 'name', c.name, 'description', c.description, 'monthlyAmountPaise', c.monthly_amount_paise, 'memberCount', c.member_count,
    'firstDueDate', c.first_due_date, 'dueDay', c.due_day, 'upiId', c.upi_id, 'payeeName', c.payee_name, 'status', c.status,
    'shuffleScheduledAt', c.shuffle_scheduled_at, 'resultHash', (select sr.result_hash from public.shuffle_runs sr where sr.chitti_id = c.id order by sr.run_number desc limit 1), 'createdAt', c.created_at,
    'invitations', case when public.is_chitti_admin(c.id) then coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.invited_name, 'email', i.invited_email, 'phone', i.invited_phone, 'status', i.status, 'lateJoin', i.late_join) order by i.created_at) from public.invitations i where i.chitti_id = c.id), '[]'::jsonb) else '[]'::jsonb end,
    'members', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name,
      'email', case when public.is_chitti_admin(c.id) then p.email else '' end, 'phone', case when public.is_chitti_admin(c.id) then p.phone else '' end,
      'avatarUri', p.avatar_url, 'joined', true, 'payoutPosition', cm.payout_position, 'approval', coalesce(sa.status, 'pending'), 'isAdmin', cm.is_admin) order by coalesce(cm.payout_position, 99), p.display_name)
      from public.chitti_members cm join public.profiles p on p.id = cm.user_id
      left join public.shuffle_runs sr on sr.id = (select id from public.shuffle_runs where chitti_id = c.id order by run_number desc limit 1)
      left join public.shuffle_approvals sa on sa.shuffle_run_id = sr.id and sa.member_id = p.id where cm.chitti_id = c.id), '[]'::jsonb),
    'rounds', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'number', r.round_number, 'dueDate', r.due_date, 'recipientMemberId', r.recipient_id,
      'status', r.status, 'payoutStatus', p.status, 'confirmedCount', (select count(*) from public.contributions cc where cc.round_id = r.id and cc.status = 'confirmed'),
      'contributions', coalesce((select jsonb_agg(jsonb_build_object('id', cc.id, 'memberId', cc.member_id, 'status', cc.status,
        'method', case when public.is_chitti_admin(c.id) or cc.member_id = auth.uid() then cc.method else null end,
        'reference', case when public.is_chitti_admin(c.id) or cc.member_id = auth.uid() then cc.reference else null end,
        'submittedAt', cc.submitted_at, 'confirmedAt', cc.confirmed_at)) from public.contributions cc
        where cc.round_id = r.id and (public.is_chitti_admin(c.id) or cc.member_id = auth.uid())), '[]'::jsonb),
      'adjustments', coalesce((select jsonb_agg(jsonb_build_object('id', pa.id, 'recipientMemberId', pa.recipient_id,
        'sourceMemberId', pa.source_member_id, 'amountPaise', pa.amount_paise, 'status', pa.status,
        'paidAt', pa.paid_at)) from public.payout_adjustments pa where pa.round_id = r.id
        and (public.is_chitti_admin(c.id) or pa.recipient_id = auth.uid() or pa.source_member_id = auth.uid())), '[]'::jsonb)) order by r.round_number)
      from public.rounds r join public.payouts p on p.round_id = r.id where r.chitti_id = c.id), '[]'::jsonb)
  ) order by c.created_at desc) from my_chittis c), '[]'::jsonb),
  'notifications', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'userId', n.user_id, 'title', n.title, 'message', n.message, 'route', n.route, 'read', n.read_at is not null, 'createdAt', n.created_at) order by n.created_at desc) from public.notifications n where n.user_id = auth.uid()), '[]'::jsonb)
);
$$;

revoke all on function public.add_chitti_member_invitation(uuid, text, text, text) from public, anon;
grant execute on function public.add_chitti_member_invitation(uuid, text, text, text) to authenticated;
revoke all on function public.redeem_invitation(text, uuid) from public, anon;
grant execute on function public.redeem_invitation(text, uuid) to authenticated;
revoke all on function public.submit_contribution(uuid, public.payment_method, text) from public, anon;
grant execute on function public.submit_contribution(uuid, public.payment_method, text) to authenticated;
revoke all on function public.review_contribution(uuid, boolean) from public, anon;
grant execute on function public.review_contribution(uuid, boolean) to authenticated;
revoke all on function public.confirm_payout_adjustment(uuid, text) from public, anon;
grant execute on function public.confirm_payout_adjustment(uuid, text) to authenticated;
revoke all on function public.swap_payout_months(uuid, uuid, uuid) from public, anon;
grant execute on function public.swap_payout_months(uuid, uuid, uuid) to authenticated;

alter publication supabase_realtime add table public.payout_adjustments;

commit;
