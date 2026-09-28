begin;

-- Integer paise is authoritative. Legacy basis points remain display/compatibility metadata only.
alter table public.chitti_members add column contribution_amount_paise bigint check (contribution_amount_paise > 0);
alter table public.invitations add column coowner_amount_paise bigint check (coowner_amount_paise > 0);
with amounts as (
  select m.chitti_id, m.user_id,
    floor(c.monthly_amount_paise * m.contribution_share_bps / 10000.0)::bigint amount,
    c.monthly_amount_paise,
    sum(floor(c.monthly_amount_paise * m.contribution_share_bps / 10000.0)) over w allocated,
    sum(m.contribution_share_bps) over w total_bps,
    row_number() over (partition by m.chitti_id, m.payout_position order by m.contribution_share_bps desc, m.user_id) seq
  from public.chitti_members m join public.chittis c on c.id = m.chitti_id
  window w as (partition by m.chitti_id, m.payout_position)
)
update public.chitti_members m set contribution_amount_paise = a.amount +
  case when a.seq = 1 and a.total_bps = 10000 then a.monthly_amount_paise - a.allocated else 0 end
from amounts a where m.chitti_id = a.chitti_id and m.user_id = a.user_id;
update public.invitations i set coowner_amount_paise = floor(c.monthly_amount_paise * i.coowner_share_bps / 10000.0)
from public.chittis c where c.id = i.chitti_id and i.coowner_share_bps is not null;
alter table public.chitti_members alter column contribution_amount_paise set not null;
alter table public.invitations add constraint invitations_coowner_amount_check check (
  (coowner_share_bps is null and coowner_amount_paise is null)
  or (coowner_share_bps is not null and coowner_amount_paise is not null)
);

create function public.default_member_contribution_amount() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.contribution_amount_paise is null then
    select monthly_amount_paise into new.contribution_amount_paise from public.chittis where id = new.chitti_id;
  end if;
  return new;
end;
$$;
create trigger chitti_members_default_amount before insert on public.chitti_members
for each row execute function public.default_member_contribution_amount();

create function public.add_coowner_amount_invitation(
  p_chitti_id uuid, p_source_member_id uuid, p_amount_paise bigint,
  p_name text, p_email text, p_phone text, p_source_invitation_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.chittis; source public.chitti_members; parent public.invitations;
  v_position smallint; available bigint; reserved bigint; token text; invite_id uuid; bps smallint;
begin
  select * into c from public.chittis where id = p_chitti_id for update;
  if c.id is null or not public.is_chitti_admin(c.id) then raise exception 'Administrator access required'; end if;
  if c.status <> 'active' and not (c.is_imported and c.status = 'inviting' and c.locked_at is null
      and not exists(select 1 from public.rounds where chitti_id = c.id)) then
    raise exception 'Share a position in a pending existing chitti or an active chitti';
  end if;
  if num_nonnulls(p_source_member_id, p_source_invitation_id) <> 1 then raise exception 'Choose one main owner'; end if;
  if p_source_member_id is not null then
    select * into source from public.chitti_members where chitti_id = c.id and user_id = p_source_member_id;
    v_position := source.payout_position;
    available := source.contribution_amount_paise;
    select coalesce(sum(i.coowner_amount_paise), 0) into reserved from public.invitations i
    left join public.invitations inv_parent on inv_parent.id = i.coowner_source_invitation_id
    where i.chitti_id = c.id and i.status = 'pending'
      and (i.coowner_source_member_id = source.user_id or inv_parent.accepted_by = source.user_id);
  else
    select * into parent from public.invitations where id = p_source_invitation_id and chitti_id = c.id;
    if c.status <> 'inviting' or parent.status is distinct from 'pending' or parent.coowner_share_bps is not null then
      raise exception 'Choose a pending main-owner invitation';
    end if;
    v_position := parent.payout_position;
    available := c.monthly_amount_paise;
    select coalesce(sum(coowner_amount_paise), 0) into reserved from public.invitations
    where coowner_source_invitation_id = parent.id and status in ('pending', 'accepted');
  end if;
  available := available - reserved;
  if v_position is null or available is null then raise exception 'Choose an owner with an assigned payout month'; end if;
  if p_amount_paise is null or p_amount_paise < 1 or p_amount_paise >= available then
    raise exception 'Enter a positive amount below the main owner''s unreserved amount; leave at least one paise for that owner';
  end if;
  if c.status = 'active' then
    if not exists(select 1 from public.rounds r join public.round_payout_shares s on s.round_id = r.id
      where r.chitti_id = c.id and r.round_number = v_position and r.status <> 'completed'
        and s.recipient_id = source.user_id and s.status <> 'paid' and s.amount_paise > p_amount_paise * c.member_count) then
      raise exception 'The source owner must have an unpaid payout with enough remaining amount';
    end if;
    if exists(select 1 from public.contributions x join public.rounds r on r.id = x.round_id
      where r.chitti_id = c.id and r.status <> 'completed' and x.member_id = source.user_id and x.status in ('submitted', 'confirmed')) then
      raise exception 'This owner has submitted or confirmed payments; their active contribution cannot be split';
    end if;
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 80 then raise exception 'Enter a valid member name'; end if;
  if p_email is null or position('@' in p_email) < 2 then raise exception 'Enter a valid email address'; end if;
  if p_phone is null or char_length(btrim(p_phone)) < 8 then raise exception 'Enter a valid phone number'; end if;
  if exists(select 1 from public.chitti_members m join public.profiles p on p.id = m.user_id
      where m.chitti_id = c.id and lower(p.email) = lower(btrim(p_email)))
    or exists(select 1 from public.invitations where chitti_id = c.id and status = 'pending' and lower(invited_email) = lower(btrim(p_email))) then
    raise exception 'This email is already a member or has a pending invitation';
  end if;
  bps := greatest(1, least(9999, floor(p_amount_paise * 10000.0 / c.monthly_amount_paise)))::smallint;
  token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash,
    payout_position, coowner_source_member_id, coowner_source_invitation_id, coowner_share_bps, coowner_amount_paise)
  values(c.id, btrim(p_name), lower(btrim(p_email)), btrim(p_phone), extensions.digest(token, 'sha256'),
    v_position, p_source_member_id, p_source_invitation_id, bps, p_amount_paise) returning id into invite_id;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select id, 'invitation.coowner_created', 'You have a shared Chitti invitation', 'Open Chitti to review your shared position.',
    '/invite?invitation=' || invite_id, 'invite:' || invite_id from public.profiles where lower(email) = lower(btrim(p_email));
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values(auth.uid(), c.id, 'invitation.coowner_added', 'invitation', invite_id::text,
    jsonb_build_object('payout_position', v_position, 'amount_paise', p_amount_paise));
  return jsonb_build_object('invitation_id', invite_id, 'token', token, 'payout_position', v_position, 'amount_paise', p_amount_paise);
end;
$$;

-- Older clients retain percentage entry, but the stored contract is an exact amount and has no owner-count cap.
create or replace function public.add_coowner_invitation(
  p_chitti_id uuid, p_source_member_id uuid, p_share_bps smallint,
  p_name text, p_email text, p_phone text, p_source_invitation_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare amount bigint; result jsonb;
begin
  if p_share_bps is null or p_share_bps not between 1 and 9999 then raise exception 'Enter a valid share'; end if;
  select floor(monthly_amount_paise * p_share_bps / 10000.0) into amount from public.chittis where id = p_chitti_id;
  result := public.add_coowner_amount_invitation(p_chitti_id, p_source_member_id, amount, p_name, p_email, p_phone, p_source_invitation_id);
  return result || jsonb_build_object('share_bps', p_share_bps);
end;
$$;

create or replace function public.redeem_invitation(p_token text default null, p_invitation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare i public.invitations; c public.chittis; parent public.invitations; source public.chitti_members;
  source_id uuid; amount bigint; bps smallint; target_round public.rounds; payout_amount bigint;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into i from public.invitations where (p_token is not null and token_hash = extensions.digest(p_token, 'sha256'))
    or (p_invitation_id is not null and id = p_invitation_id);
  select * into c from public.chittis where id = i.chitti_id for update;
  if i.coowner_share_bps is null and not coalesce(c.is_imported and c.status in ('inviting', 'ready'), false) then
    return public.redeem_invitation_before_pending_shares(p_token, p_invitation_id);
  end if;
  select * into i from public.invitations where id = i.id for update;
  if i.id is null or i.status <> 'pending' or i.expires_at < now() then raise exception 'Invitation is invalid or expired'; end if;
  if lower(i.invited_email) <> lower(coalesce(auth.jwt()->>'email', '')) then raise exception 'Sign in with the invited Google email'; end if;
  if c.status <> 'active' and not (c.is_imported and c.status in ('inviting', 'ready') and c.locked_at is null) then
    raise exception 'This shared invitation is no longer available';
  end if;
  if i.coowner_share_bps is not null then
    amount := i.coowner_amount_paise;
    source_id := i.coowner_source_member_id;
    if i.coowner_source_invitation_id is not null then
      select * into parent from public.invitations where id = i.coowner_source_invitation_id and chitti_id = c.id;
      if parent.id is null or parent.status not in ('pending', 'accepted') then raise exception 'The main-owner invitation is unavailable'; end if;
      source_id := parent.accepted_by;
    end if;
    if source_id is not null then
      select * into source from public.chitti_members where chitti_id = c.id and user_id = source_id for update;
      if source.user_id is null or source.contribution_amount_paise <= amount then raise exception 'The shared payout is no longer available'; end if;
      i.payout_position := source.payout_position;
    end if;
    if c.status = 'active' then
      select * into target_round from public.rounds where chitti_id = c.id and round_number = i.payout_position for update;
      payout_amount := amount * c.member_count;
      if source_id is null or target_round.id is null or target_round.status = 'completed'
        or not exists(select 1 from public.round_payout_shares where round_id = target_round.id and recipient_id = source_id and status <> 'paid' and amount_paise > payout_amount) then
        raise exception 'The source owner must have an unpaid payout with enough remaining amount';
      end if;
      if exists(select 1 from public.contributions x join public.rounds r on r.id = x.round_id where r.chitti_id = c.id
        and r.status <> 'completed' and x.member_id = source_id and x.status in ('submitted', 'confirmed')) then
        raise exception 'This owner has submitted or confirmed payments; their active contribution cannot be split';
      end if;
    end if;
    if source_id is not null then
      update public.chitti_members set contribution_amount_paise = contribution_amount_paise - amount,
        contribution_share_bps = greatest(1, least(10000, floor((contribution_amount_paise - amount) * 10000.0 / c.monthly_amount_paise)))
      where chitti_id = c.id and user_id = source_id;
    end if;
  else
    select c.monthly_amount_paise - coalesce(sum(coowner_amount_paise), 0) into amount from public.invitations
    where coowner_source_invitation_id = i.id and status = 'accepted';
  end if;
  if amount is null or amount < 1 or i.payout_position is null or i.payout_position not between 1 and c.member_count then raise exception 'Invalid shared amount or payout position'; end if;
  bps := greatest(1, least(10000, floor(amount * 10000.0 / c.monthly_amount_paise)))::smallint;
  insert into public.chitti_members(chitti_id, user_id, payout_position, contribution_share_bps, contribution_amount_paise)
  values(c.id, auth.uid(), i.payout_position, bps, amount);
  if c.status = 'active' then
    update public.contributions x set amount_paise = coalesce(x.amount_paise, source.contribution_amount_paise) - amount
    from public.rounds r where x.round_id = r.id and r.chitti_id = c.id and r.status <> 'completed' and x.member_id = source_id;
    insert into public.contributions(round_id, member_id, amount_paise)
    select r.id, auth.uid(), amount from public.rounds r where r.chitti_id = c.id and r.status <> 'completed';
    update public.round_payout_shares set amount_paise = amount_paise - payout_amount,
      share_bps = greatest(1, least(10000, floor((source.contribution_amount_paise - amount) * 10000.0 / c.monthly_amount_paise)))
    where round_id = target_round.id and recipient_id = source_id;
    insert into public.round_payout_shares(round_id, recipient_id, amount_paise, share_bps, status)
    select target_round.id, auth.uid(), payout_amount, bps, status from public.payouts where round_id = target_round.id;
  end if;
  update public.profiles set phone = case when btrim(phone) = '' then i.invited_phone else phone end where id = auth.uid();
  update public.invitations set status = 'accepted', accepted_by = auth.uid(), accepted_at = now() where id = i.id;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  values(c.admin_id, 'invitation.accepted', i.invited_name || ' joined', 'A member accepted the invitation.', '/chitti/' || c.id, 'joined:' || i.id);
  if source_id is not null then
    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    values(source_id, 'payout.share_changed', 'Your Chitti contribution changed', 'A co-owner joined your position. Open Chitti to review your updated amount.', '/chitti/' || c.id, 'share-changed:' || i.id);
  end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values(auth.uid(), c.id, 'invitation.accepted', 'invitation', i.id::text, jsonb_build_object('amount_paise', amount, 'payout_position', i.payout_position));
  return c.id;
end;
$$;

revoke all on function public.default_member_contribution_amount() from public, anon, authenticated;
revoke all on function public.add_coowner_amount_invitation(uuid, uuid, bigint, text, text, text, uuid) from public, anon;
grant execute on function public.add_coowner_amount_invitation(uuid, uuid, bigint, text, text, text, uuid) to authenticated;

create or replace function public.activate_imported_chitti(p_chitti_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.chittis;
begin
  select * into c from public.chittis where id = p_chitti_id for update;
  if c.id is null or not c.is_imported then raise exception 'Imported chitti not found'; end if;
  if c.status not in ('inviting', 'ready') then return; end if;
  if exists(select 1 from public.invitations where chitti_id = c.id and status = 'pending') then return; end if;
  if (select count(distinct payout_position) from public.chitti_members where chitti_id = c.id) <> c.member_count then return; end if;
  if exists(select 1 from generate_series(1, c.member_count) slot(position)
    where (select coalesce(sum(contribution_amount_paise), 0) from public.chitti_members where chitti_id = c.id and payout_position = slot.position) <> c.monthly_amount_paise) then
    raise exception 'Every payout position must have contribution amounts totaling the full monthly amount';
  end if;
  insert into public.rounds(chitti_id, round_number, due_date, recipient_id, status)
  select c.id, m.payout_position, (c.first_due_date + make_interval(months => m.payout_position - 1))::date, m.user_id,
    case when m.payout_position <= c.imported_completed_months then 'completed'::public.round_status
      when m.payout_position = c.imported_completed_months + 1 then 'collecting'::public.round_status else 'upcoming'::public.round_status end
  from (select distinct on (payout_position) * from public.chitti_members where chitti_id = c.id
    order by payout_position, is_admin desc, joined_at, user_id) m;
  insert into public.contributions(round_id, member_id, amount_paise)
  select r.id, m.user_id, m.contribution_amount_paise from public.rounds r
  cross join public.chitti_members m where r.chitti_id = c.id and m.chitti_id = c.id
    and r.round_number > c.imported_completed_months;
  insert into public.payouts(round_id, status)
  select id, case when round_number <= c.imported_completed_months then 'paid'::public.payout_status else 'blocked'::public.payout_status end
  from public.rounds where chitti_id = c.id;
  update public.chittis set status = case when imported_completed_months = member_count then 'completed'::public.chitti_status else 'active'::public.chitti_status end, locked_at = now() where id = c.id;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), c.id, 'chitti.import_activated', 'chitti', c.id::text, jsonb_build_object('completed_months', c.imported_completed_months));
  perform public.notify_chitti_members(c.id, 'chitti.import_activated', 'Existing chitti is ready',
    'All owners joined. The saved payout order and individual contributions are now active.', '/chitti/' || c.id, c.id::text, null);
end;
$$;

create or replace function public.create_round_payout_share()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.chittis;
begin
  select * into c from public.chittis where id = new.chitti_id;
  insert into public.round_payout_shares(round_id, recipient_id, amount_paise, share_bps, status, paid_at)
  select new.id, user_id, contribution_amount_paise * c.member_count, contribution_share_bps,
    case when new.status = 'completed' then 'paid'::public.payout_status
      when new.status = 'ready_for_payout' then 'ready'::public.payout_status else 'blocked'::public.payout_status end,
    case when new.status = 'completed' then now() else null end
  from public.chitti_members where chitti_id = c.id and payout_position = new.round_number;
  return new;
end;
$$;

-- New rounds created by late-join flows must also use each owner's amount, not a full position.
create function public.default_contribution_amount() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.amount_paise is null then
    select m.contribution_amount_paise into new.amount_paise from public.chitti_members m
    join public.rounds r on r.chitti_id = m.chitti_id where r.id = new.round_id and m.user_id = new.member_id;
  end if;
  return new;
end;
$$;
create trigger contributions_default_amount before insert on public.contributions
for each row execute function public.default_contribution_amount();
revoke all on function public.default_contribution_amount() from public, anon, authenticated;

alter function public.get_app_snapshot() rename to get_app_snapshot_before_amount_shares;
revoke all on function public.get_app_snapshot_before_amount_shares() from public, anon, authenticated;
create function public.get_app_snapshot() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare snapshot jsonb;
begin
  snapshot := public.get_app_snapshot_before_amount_shares();
  snapshot := jsonb_set(snapshot, '{pendingInvitations}', coalesce((
    select jsonb_agg(entry || jsonb_build_object('coOwnerAmountPaise', i.coowner_amount_paise,
      'contributionAmountPaise', coalesce(i.coowner_amount_paise,
        c.monthly_amount_paise - (select coalesce(sum(coowner_amount_paise),0) from public.invitations
          where coowner_source_invitation_id = i.id and status in ('pending','accepted')))))
    from jsonb_array_elements(snapshot->'pendingInvitations') entry
    join public.invitations i on i.id = (entry->>'id')::uuid join public.chittis c on c.id = i.chitti_id
  ), '[]'::jsonb));
  return jsonb_set(snapshot, '{chittis}', coalesce((
    select jsonb_agg(entry || jsonb_build_object(
      'members', coalesce((select jsonb_agg(m || jsonb_build_object('contributionAmountPaise', member.contribution_amount_paise))
        from jsonb_array_elements(entry->'members') m join public.chitti_members member
        on member.chitti_id = (entry->>'id')::uuid and member.user_id = (m->>'id')::uuid), '[]'::jsonb),
      'invitations', coalesce((select jsonb_agg(i || jsonb_build_object('coOwnerAmountPaise', invitation.coowner_amount_paise))
        from jsonb_array_elements(entry->'invitations') i join public.invitations invitation on invitation.id = (i->>'id')::uuid), '[]'::jsonb)
    )) from jsonb_array_elements(snapshot->'chittis') entry
  ), '[]'::jsonb));
end;
$$;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

create or replace function public.get_reports()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
with target_users as (
  select auth.uid() as user_id
  union
  select member.user_id
  from public.chittis chitti
  join public.chitti_members member on member.chitti_id = chitti.id
  where chitti.admin_id = auth.uid()
), report_users as (
  select target.user_id, profile.display_name, profile.email, profile.phone, profile.avatar_url
  from target_users target
  join public.profiles profile on profile.id = target.user_id
), user_stats as (
  select report_user.user_id,
    count(contribution.id) filter (
      where contribution.status = 'confirmed' and contribution.confirmed_on_time is true
    )::int as on_time,
    count(contribution.id) filter (
      where contribution.status = 'confirmed' and contribution.confirmed_on_time is false
    )::int as late,
    count(contribution.id) filter (
      where round_item.due_date < (now() at time zone 'Asia/Kolkata')::date
        and contribution.status <> 'confirmed'
    )::int as missed,
    coalesce(sum(coalesce(contribution.amount_paise, chitti.monthly_amount_paise)) filter (where contribution.status = 'confirmed'), 0)::bigint as confirmed_amount,
    coalesce(sum(coalesce(contribution.amount_paise, chitti.monthly_amount_paise)) filter (
      where round_item.due_date < (now() at time zone 'Asia/Kolkata')::date
        and contribution.status <> 'confirmed'
    ), 0)::bigint as overdue_amount
  from report_users report_user
  left join public.contributions contribution on contribution.member_id = report_user.user_id
  left join public.rounds round_item on round_item.id = contribution.round_id
  left join public.chittis chitti on chitti.id = round_item.chitti_id
    and (report_user.user_id = auth.uid() or chitti.admin_id = auth.uid())
  where chitti.id is not null or contribution.id is null
  group by report_user.user_id
)
select coalesce(jsonb_agg(jsonb_build_object(
  'userId', report_user.user_id,
  'name', report_user.display_name,
  'email', report_user.email,
  'phone', report_user.phone,
  'avatarUri', report_user.avatar_url,
  'chittiCount', (
    select count(*)::int from public.chitti_members membership
    join public.chittis chitti on chitti.id = membership.chitti_id
    where membership.user_id = report_user.user_id
      and (report_user.user_id = auth.uid() or chitti.admin_id = auth.uid())
  ),
  'activeChittis', (
    select count(*)::int from public.chitti_members membership
    join public.chittis chitti on chitti.id = membership.chitti_id
    where membership.user_id = report_user.user_id
      and chitti.status = 'active'
      and (report_user.user_id = auth.uid() or chitti.admin_id = auth.uid())
  ),
  'completedChittis', (
    select count(*)::int from public.chitti_members membership
    join public.chittis chitti on chitti.id = membership.chitti_id
    where membership.user_id = report_user.user_id
      and chitti.status = 'completed'
      and (report_user.user_id = auth.uid() or chitti.admin_id = auth.uid())
  ),
  'onTimePayments', stats.on_time,
  'latePayments', stats.late,
  'missedDueDates', stats.missed,
  'assessedPayments', stats.on_time + stats.late + stats.missed,
  'reliabilityScore', case
    when stats.on_time + stats.late + stats.missed = 0 then null
    else round((stats.on_time::numeric * 10) / (stats.on_time + stats.late + stats.missed), 1)
  end,
  'confirmedAmountPaise', stats.confirmed_amount,
  'overdueAmountPaise', stats.overdue_amount,
  'chittis', coalesce((
    select jsonb_agg(jsonb_build_object(
      'chittiId', chitti.id,
      'name', chitti.name,
      'status', chitti.status,
      'monthlyAmountPaise', membership.contribution_amount_paise,
      'totalAmountPaise', chitti.monthly_amount_paise * chitti.member_count,
      'startDate', chitti.start_date,
      'endDate', chitti.end_date,
      'payoutPosition', membership.payout_position,
      'payoutDate', payout_round.due_date,
      'payoutStatus', coalesce(owner_payout.status, payout.status),
      'onTimePayments', chitti_stats.on_time,
      'latePayments', chitti_stats.late,
      'missedDueDates', chitti_stats.missed,
      'confirmedAmountPaise', chitti_stats.confirmed_amount,
      'overdueAmountPaise', chitti_stats.overdue_amount
    ) order by chitti.created_at desc)
    from public.chitti_members membership
    join public.chittis chitti on chitti.id = membership.chitti_id
    left join public.rounds payout_round
      on payout_round.chitti_id = chitti.id and payout_round.round_number = membership.payout_position
    left join public.payouts payout on payout.round_id = payout_round.id
    left join public.round_payout_shares owner_payout on owner_payout.round_id = payout_round.id and owner_payout.recipient_id = report_user.user_id
    cross join lateral (
      select
        count(contribution.id) filter (
          where contribution.status = 'confirmed' and contribution.confirmed_on_time is true
        )::int as on_time,
        count(contribution.id) filter (
          where contribution.status = 'confirmed' and contribution.confirmed_on_time is false
        )::int as late,
        count(contribution.id) filter (
          where round_item.due_date < (now() at time zone 'Asia/Kolkata')::date
            and contribution.status <> 'confirmed'
        )::int as missed,
        coalesce(sum(coalesce(contribution.amount_paise, chitti.monthly_amount_paise)) filter (where contribution.status = 'confirmed'), 0)::bigint as confirmed_amount,
        coalesce(sum(coalesce(contribution.amount_paise, chitti.monthly_amount_paise)) filter (
          where round_item.due_date < (now() at time zone 'Asia/Kolkata')::date
            and contribution.status <> 'confirmed'
        ), 0)::bigint as overdue_amount
      from public.contributions contribution
      join public.rounds round_item on round_item.id = contribution.round_id
      where contribution.member_id = report_user.user_id
        and round_item.chitti_id = chitti.id
    ) chitti_stats
    where membership.user_id = report_user.user_id
      and (report_user.user_id = auth.uid() or chitti.admin_id = auth.uid())
  ), '[]'::jsonb)
) order by case when report_user.user_id = auth.uid() then 0 else 1 end, report_user.display_name), '[]'::jsonb)
from report_users report_user
join user_stats stats on stats.user_id = report_user.user_id;
$$;

commit;
