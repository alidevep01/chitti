begin;

alter table public.chitti_members
  add column contribution_share_bps smallint not null default 10000,
  add constraint chitti_members_contribution_share_check
    check (contribution_share_bps between 1 and 10000);

alter table public.chitti_members
  drop constraint if exists chitti_members_chitti_id_payout_position_key;

create index chitti_members_chitti_payout_position_idx
  on public.chitti_members(chitti_id, payout_position);

alter table public.invitations
  add column coowner_source_member_id uuid references public.profiles(id) on delete restrict,
  add column coowner_share_bps smallint,
  add constraint invitations_coowner_share_check check (
    (coowner_source_member_id is null and coowner_share_bps is null)
    or (coowner_source_member_id is not null and coowner_share_bps between 1 and 9999)
  );

alter table public.contributions
  add column amount_paise bigint check (amount_paise is null or amount_paise > 0);

create table public.round_payout_shares (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.rounds(id) on delete restrict,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  amount_paise bigint not null check (amount_paise > 0),
  share_bps smallint not null check (share_bps between 1 and 10000),
  status public.payout_status not null default 'blocked',
  reference text check (char_length(reference) <= 100),
  confirmed_by uuid references public.profiles(id) on delete restrict,
  paid_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (round_id, recipient_id)
);
create index round_payout_shares_round_status_idx on public.round_payout_shares(round_id, status);
create trigger round_payout_shares_touch before update on public.round_payout_shares
for each row execute function public.touch_updated_at();

insert into public.round_payout_shares(round_id, recipient_id, amount_paise, share_bps, status, reference, confirmed_by, paid_at)
select round_item.id, round_item.recipient_id,
  chitti.monthly_amount_paise * chitti.member_count,
  10000,
  payout.status,
  payout.reference,
  payout.confirmed_by,
  payout.paid_at
from public.rounds round_item
join public.chittis chitti on chitti.id = round_item.chitti_id
join public.payouts payout on payout.round_id = round_item.id;

create function public.create_round_payout_share()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_member public.chitti_members;
  v_pot bigint;
  v_amount bigint;
  v_allocated bigint := 0;
  v_first_share_id uuid;
begin
  select * into v_chitti from public.chittis where id = new.chitti_id;
  v_pot := v_chitti.monthly_amount_paise * v_chitti.member_count;
  for v_member in
    select * from public.chitti_members
    where chitti_id = new.chitti_id and payout_position = new.round_number
    order by is_admin desc, joined_at, user_id
  loop
    v_amount := floor(v_pot * v_member.contribution_share_bps / 10000.0)::bigint;
    insert into public.round_payout_shares(round_id, recipient_id, amount_paise, share_bps)
    values (new.id, v_member.user_id, v_amount, v_member.contribution_share_bps)
    returning id into v_first_share_id;
    v_allocated := v_allocated + v_amount;
  end loop;
  if v_allocated <> v_pot then
    update public.round_payout_shares
    set amount_paise = amount_paise + (v_pot - v_allocated)
    where id = v_first_share_id;
  end if;
  return new;
end;
$$;

create trigger rounds_create_payout_shares
after insert on public.rounds
for each row execute function public.create_round_payout_share();

alter table public.round_payout_shares enable row level security;
create policy round_payout_shares_affected_select on public.round_payout_shares
for select to authenticated using (
  recipient_id = auth.uid()
  or public.is_chitti_admin((select round_item.chitti_id from public.rounds round_item where round_item.id = round_id))
);
grant select on public.round_payout_shares to authenticated;

create function public.add_coowner_invitation(
  p_chitti_id uuid,
  p_source_member_id uuid,
  p_share_bps smallint,
  p_name text,
  p_email text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_source public.chitti_members;
  v_round public.rounds;
  v_invitation_id uuid;
  v_token text;
begin
  select * into v_chitti from public.chittis where id = p_chitti_id for update;
  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if v_chitti.status <> 'active' then
    raise exception 'Add a co-owner after the payout order is active';
  end if;
  select * into v_source from public.chitti_members
  where chitti_id = p_chitti_id and user_id = p_source_member_id for update;
  if v_source.user_id is null or v_source.payout_position is null then
    raise exception 'Choose an owner with an assigned payout month';
  end if;
  if p_share_bps < 1 or p_share_bps >= v_source.contribution_share_bps then
    raise exception 'The new share must be smaller than the selected owner''s current share';
  end if;
  select * into v_round from public.rounds
  where chitti_id = p_chitti_id and round_number = v_source.payout_position;
  if v_round.status = 'completed' or exists(
    select 1 from public.payouts payout where payout.round_id = v_round.id and payout.status = 'paid'
  ) then
    raise exception 'A completed payout month cannot be shared';
  end if;
  if char_length(btrim(p_name)) not between 2 and 80 then raise exception 'Enter a valid member name'; end if;
  if position('@' in p_email) < 2 then raise exception 'Enter a valid email address'; end if;
  if char_length(btrim(p_phone)) < 8 then raise exception 'Enter a valid phone number'; end if;
  if exists(
    select 1 from public.chitti_members member join public.profiles profile on profile.id = member.user_id
    where member.chitti_id = p_chitti_id and lower(profile.email) = lower(btrim(p_email))
  ) or exists(
    select 1 from public.invitations invitation
    where invitation.chitti_id = p_chitti_id
      and lower(invitation.invited_email) = lower(btrim(p_email))
      and invitation.status = 'pending'
  ) then
    raise exception 'This email is already a member or has a pending invitation';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.invitations(
    chitti_id, invited_name, invited_email, invited_phone, token_hash,
    coowner_source_member_id, coowner_share_bps
  ) values (
    p_chitti_id, btrim(p_name), lower(btrim(p_email)), btrim(p_phone),
    extensions.digest(v_token, 'sha256'), p_source_member_id, p_share_bps
  ) returning id into v_invitation_id;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select id, 'invitation.coowner_created', 'You have a shared Chitti invitation',
    'You were invited to share payout month ' || v_source.payout_position ||
      ' with a ' || trim(to_char(p_share_bps / 100.0, 'FM990D99')) || '% share.',
    '/invite?invitation=' || v_invitation_id, 'invite:' || v_invitation_id
  from public.profiles where lower(email) = lower(btrim(p_email))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), p_chitti_id, 'invitation.coowner_added', 'invitation', v_invitation_id::text,
    jsonb_build_object('source_member_id', p_source_member_id, 'payout_position', v_source.payout_position,
      'share_bps', p_share_bps));

  return jsonb_build_object(
    'invitation_id', v_invitation_id,
    'token', v_token,
    'payout_position', v_source.payout_position,
    'share_bps', p_share_bps
  );
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
  v_source public.chitti_members;
  v_email text;
  v_joined int;
  v_new_position int;
  v_new_round_id uuid;
  v_contribution record;
  v_elapsed_count int;
  v_share_amount bigint;
  v_payout_amount bigint;
  v_shared_round public.rounds;
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

  if v_invite.coowner_source_member_id is not null then
    if v_chitti.status <> 'active' then raise exception 'This shared-slot invitation is no longer available'; end if;
    select * into v_source from public.chitti_members
    where chitti_id = v_invite.chitti_id and user_id = v_invite.coowner_source_member_id for update;
    if v_source.user_id is null or v_source.payout_position is null
       or v_invite.coowner_share_bps >= v_source.contribution_share_bps then
      raise exception 'The shared payout is no longer available';
    end if;
    select * into v_shared_round from public.rounds
    where chitti_id = v_invite.chitti_id and round_number = v_source.payout_position for update;
    if v_shared_round.status = 'completed' then raise exception 'The shared payout month is already completed'; end if;

    v_share_amount := floor(v_chitti.monthly_amount_paise * v_invite.coowner_share_bps / 10000.0)::bigint;
    v_payout_amount := floor((v_chitti.monthly_amount_paise * v_chitti.member_count) * v_invite.coowner_share_bps / 10000.0)::bigint;
    if v_share_amount < 1 or v_payout_amount < 1 then raise exception 'The selected share is too small'; end if;

    update public.chitti_members
    set contribution_share_bps = contribution_share_bps - v_invite.coowner_share_bps
    where chitti_id = v_invite.chitti_id and user_id = v_source.user_id;
    insert into public.chitti_members(chitti_id, user_id, payout_position, contribution_share_bps)
    values (v_invite.chitti_id, auth.uid(), v_source.payout_position, v_invite.coowner_share_bps);

    update public.contributions contribution
    set amount_paise = coalesce(contribution.amount_paise, v_chitti.monthly_amount_paise) - v_share_amount
    from public.rounds round_item
    where contribution.round_id = round_item.id
      and round_item.chitti_id = v_invite.chitti_id
      and round_item.status <> 'completed'
      and contribution.member_id = v_source.user_id
      and contribution.status in ('due', 'rejected', 'overdue');
    insert into public.contributions(round_id, member_id, status, amount_paise)
    select round_item.id, auth.uid(),
      case when round_item.due_date < (now() at time zone 'Asia/Kolkata')::date
        then 'overdue'::public.contribution_status else 'due'::public.contribution_status end,
      v_share_amount
    from public.rounds round_item
    where round_item.chitti_id = v_invite.chitti_id
      and round_item.status <> 'completed'
      and exists(
        select 1 from public.contributions source_contribution
        where source_contribution.round_id = round_item.id
          and source_contribution.member_id = v_source.user_id
          and source_contribution.status in ('due', 'rejected', 'overdue')
      );

    update public.round_payout_shares
    set amount_paise = amount_paise - v_payout_amount,
        share_bps = share_bps - v_invite.coowner_share_bps
    where round_id = v_shared_round.id and recipient_id = v_source.user_id;
    insert into public.round_payout_shares(round_id, recipient_id, amount_paise, share_bps, status)
    select v_shared_round.id, auth.uid(), v_payout_amount, v_invite.coowner_share_bps, payout.status
    from public.payouts payout where payout.round_id = v_shared_round.id;

    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    values (v_source.user_id, 'payout.share_changed', 'Your Chitti share changed',
      v_invite.invited_name || ' now co-owns payout month ' || v_source.payout_position ||
        '. Your remaining share is ' || trim(to_char((v_source.contribution_share_bps - v_invite.coowner_share_bps) / 100.0, 'FM990D99')) || '%.',
      '/chitti/' || v_invite.chitti_id, 'share-changed:' || v_invite.id);
  elsif v_invite.late_join then
    v_new_position := v_chitti.member_count + 1;
    insert into public.chitti_members(chitti_id, user_id, payout_position)
    values (v_invite.chitti_id, auth.uid(), v_new_position);
    update public.chittis set member_count = v_new_position where id = v_invite.chitti_id;

    insert into public.contributions(round_id, member_id, status)
    select r.id, auth.uid(), case when r.status = 'completed' or r.due_date < (now() at time zone 'Asia/Kolkata')::date
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

    update public.rounds set status = 'collecting' where chitti_id = v_invite.chitti_id and status = 'ready_for_payout';
    update public.payouts payout set status = 'blocked' from public.rounds round_item
    where round_item.id = payout.round_id and round_item.chitti_id = v_invite.chitti_id
      and round_item.status = 'collecting' and payout.status = 'ready';
    update public.round_payout_shares share set status = 'blocked' from public.rounds round_item
    where round_item.id = share.round_id and round_item.chitti_id = v_invite.chitti_id
      and round_item.status = 'collecting' and share.status = 'ready';

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
    case when v_invite.coowner_source_member_id is not null then 'A co-owner accepted the shared payout invitation.'
      else 'A member accepted the invitation.' end,
    '/chitti/' || v_invite.chitti_id, 'joined:' || v_invite.id
  from public.chittis where id = v_invite.chitti_id;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), v_invite.chitti_id, 'invitation.accepted', 'invitation', v_invite.id::text,
    jsonb_build_object('late_join', v_invite.late_join, 'new_position', v_new_position,
      'coowner_share_bps', v_invite.coowner_share_bps, 'source_member_id', v_invite.coowner_source_member_id));
  return v_invite.chitti_id;
end;
$$;

create function public.finish_round_after_shared_payout(p_round_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.rounds;
  v_remaining int;
begin
  select * into v_round from public.rounds where id = p_round_id for update;
  if exists(select 1 from public.round_payout_shares where round_id = p_round_id and status <> 'paid') then return; end if;
  update public.payouts set status = 'paid', confirmed_by = auth.uid(), paid_at = now() where round_id = p_round_id;
  update public.rounds set status = 'completed' where id = p_round_id;
  update public.rounds set status = 'collecting'
  where chitti_id = v_round.chitti_id and round_number = v_round.round_number + 1
    and due_date <= (now() at time zone 'Asia/Kolkata')::date and status = 'upcoming';
  select count(*) into v_remaining from public.rounds where chitti_id = v_round.chitti_id and status <> 'completed';
  if v_remaining = 0 then update public.chittis set status = 'completed' where id = v_round.chitti_id; end if;
  perform public.notify_chitti_members(v_round.chitti_id, 'payout.confirmed', 'Monthly payout delivered',
    'The administrator recorded every share of this month''s payout as delivered.',
    '/chitti/' || v_round.chitti_id, p_round_id::text, null);
end;
$$;

create function public.confirm_payout_share(p_payout_share_id uuid, p_reference text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_share public.round_payout_shares;
  v_round public.rounds;
begin
  select * into v_share from public.round_payout_shares where id = p_payout_share_id for update;
  select * into v_round from public.rounds where id = v_share.round_id;
  if v_share.id is null or not public.is_chitti_admin(v_round.chitti_id) then raise exception 'Administrator access required'; end if;
  if not exists(select 1 from public.payouts where round_id = v_round.id and status = 'ready') then
    raise exception 'Payout is not ready';
  end if;
  update public.round_payout_shares
  set status = 'paid', reference = nullif(p_reference, ''), confirmed_by = auth.uid(), paid_at = now()
  where id = p_payout_share_id and status = 'ready';
  if not found then raise exception 'This payout share is not ready'; end if;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  values (v_share.recipient_id, 'payout.share_confirmed', 'Your payout was delivered',
    'The administrator recorded your payout share as delivered.', '/chitti/' || v_round.chitti_id,
    'payout-share:' || p_payout_share_id);
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), v_round.chitti_id, 'payout.share_confirmed', 'round_payout_share', p_payout_share_id::text,
    jsonb_build_object('recipient_id', v_share.recipient_id, 'amount_paise', v_share.amount_paise));
  perform public.finish_round_after_shared_payout(v_round.id);
end;
$$;

create or replace function public.confirm_payout(p_round_id uuid, p_reference text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.rounds;
  v_share public.round_payout_shares;
begin
  select * into v_round from public.rounds where id = p_round_id for update;
  if not public.is_chitti_admin(v_round.chitti_id) then raise exception 'Administrator access required'; end if;
  if (select count(*) from public.round_payout_shares where round_id = p_round_id) <> 1 then
    raise exception 'Confirm each co-owner payout separately';
  end if;
  select * into v_share from public.round_payout_shares where round_id = p_round_id;
  perform public.confirm_payout_share(v_share.id, p_reference);
end;
$$;

create or replace function public.review_contribution(p_contribution_id uuid, p_accepted boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.rounds;
  v_chitti_id uuid;
  v_remaining int;
  v_adjustment public.payout_adjustments;
begin
  select round_item.* into v_round
  from public.contributions contribution
  join public.rounds round_item on round_item.id = contribution.round_id
  where contribution.id = p_contribution_id;
  v_chitti_id := v_round.chitti_id;
  if not public.is_chitti_admin(v_chitti_id) then raise exception 'Administrator access required'; end if;
  update public.contributions
  set status = case when p_accepted then 'confirmed'::public.contribution_status else 'rejected'::public.contribution_status end,
    reviewed_by = auth.uid(), confirmed_at = case when p_accepted then now() else null end,
    confirmed_on_time = case when p_accepted then (submitted_at at time zone 'Asia/Kolkata')::date <= v_round.due_date else null end
  where id = p_contribution_id and status = 'submitted';
  if not found then raise exception 'Contribution is not awaiting review'; end if;
  if p_accepted then
    update public.payout_adjustments set status = 'ready'
    where contribution_id = p_contribution_id and status = 'awaiting_contribution' returning * into v_adjustment;
    if v_adjustment.id is not null then
      insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
      values (v_adjustment.recipient_id, 'payout.topup_ready', 'An additional payout is ready',
        'A late member''s catch-up contribution was confirmed.', '/chitti/' || v_chitti_id,
        'topup-ready:' || v_adjustment.id);
    end if;
    if v_round.status <> 'completed' then
      select count(*) into v_remaining from public.contributions where round_id = v_round.id and status <> 'confirmed';
      if v_remaining = 0 then
        update public.rounds set status = 'ready_for_payout' where id = v_round.id;
        update public.payouts set status = 'ready' where round_id = v_round.id;
        update public.round_payout_shares set status = 'ready' where round_id = v_round.id and status = 'blocked';
      end if;
    end if;
  end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), v_chitti_id, 'contribution.reviewed', 'contribution', p_contribution_id::text,
    jsonb_build_object('accepted', p_accepted, 'confirmed_on_time', case when p_accepted
      then (select confirmed_on_time from public.contributions where id = p_contribution_id) else null end));
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select member_id, 'contribution.reviewed', case when p_accepted then 'Payment confirmed' else 'Payment needs attention' end,
    case when p_accepted then 'The administrator confirmed your contribution.' else 'The administrator could not confirm your contribution. Please review it.' end,
    '/chitti/' || v_chitti_id, 'reviewed:' || p_contribution_id || ':' || p_accepted
  from public.contributions where id = p_contribution_id
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

alter function public.get_app_snapshot() rename to get_app_snapshot_without_shared_owners;

create function public.get_app_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_snapshot jsonb;
begin
  v_snapshot := public.get_app_snapshot_without_shared_owners();
  return jsonb_set(
    v_snapshot,
    '{chittis}',
    coalesce((
      select jsonb_agg(
        chitti_item || jsonb_build_object(
          'members', coalesce((
            select jsonb_agg(member_item || jsonb_build_object(
              'contributionShareBps', membership.contribution_share_bps
            ) order by member_order)
            from jsonb_array_elements(chitti_item->'members') with ordinality member_items(member_item, member_order)
            join public.chitti_members membership
              on membership.chitti_id = (chitti_item->>'id')::uuid
             and membership.user_id = (member_item->>'id')::uuid
          ), '[]'::jsonb),
          'invitations', coalesce((
            select jsonb_agg(invitation_item || jsonb_build_object(
              'coOwnerSourceMemberId', invitation.coowner_source_member_id,
              'coOwnerShareBps', invitation.coowner_share_bps,
              'payoutPosition', coalesce(invitation.payout_position, source_membership.payout_position)
            ) order by invitation_order)
            from jsonb_array_elements(chitti_item->'invitations') with ordinality invitation_items(invitation_item, invitation_order)
            join public.invitations invitation on invitation.id = (invitation_item->>'id')::uuid
            left join public.chitti_members source_membership
              on source_membership.chitti_id = invitation.chitti_id
             and source_membership.user_id = invitation.coowner_source_member_id
          ), '[]'::jsonb),
          'rounds', coalesce((
            select jsonb_agg(round_item || jsonb_build_object(
              'contributions', coalesce((
                select jsonb_agg(contribution_item || jsonb_build_object(
                  'amountPaise', coalesce(contribution.amount_paise, (chitti_item->>'monthlyAmountPaise')::bigint)
                ) order by contribution_order)
                from jsonb_array_elements(round_item->'contributions') with ordinality contribution_items(contribution_item, contribution_order)
                join public.contributions contribution on contribution.id = (contribution_item->>'id')::uuid
              ), '[]'::jsonb),
              'payoutShares', coalesce((
                select jsonb_agg(jsonb_build_object(
                  'id', share.id,
                  'recipientMemberId', share.recipient_id,
                  'amountPaise', share.amount_paise,
                  'shareBps', share.share_bps,
                  'status', share.status,
                  'paidAt', share.paid_at
                ) order by share.id)
                from public.round_payout_shares share where share.round_id = (round_item->>'id')::uuid
              ), '[]'::jsonb)
            ) order by round_order)
            from jsonb_array_elements(chitti_item->'rounds') with ordinality round_items(round_item, round_order)
          ), '[]'::jsonb)
        ) order by chitti_order
      )
      from jsonb_array_elements(v_snapshot->'chittis') with ordinality chitti_items(chitti_item, chitti_order)
    ), '[]'::jsonb),
    true
  );
end;
$$;

revoke all on function public.create_round_payout_share() from public, anon, authenticated;
revoke all on function public.finish_round_after_shared_payout(uuid) from public, anon, authenticated;
revoke all on function public.add_coowner_invitation(uuid, uuid, smallint, text, text, text) from public, anon;
grant execute on function public.add_coowner_invitation(uuid, uuid, smallint, text, text, text) to authenticated;
revoke all on function public.confirm_payout_share(uuid, text) from public, anon;
grant execute on function public.confirm_payout_share(uuid, text) to authenticated;
revoke all on function public.redeem_invitation(text, uuid) from public, anon;
grant execute on function public.redeem_invitation(text, uuid) to authenticated;
revoke all on function public.review_contribution(uuid, boolean) from public, anon;
grant execute on function public.review_contribution(uuid, boolean) to authenticated;
revoke all on function public.confirm_payout(uuid, text) from public, anon;
grant execute on function public.confirm_payout(uuid, text) to authenticated;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

alter publication supabase_realtime add table public.round_payout_shares;

commit;
