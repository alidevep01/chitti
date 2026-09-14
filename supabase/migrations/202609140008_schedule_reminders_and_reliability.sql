begin;

alter table public.chittis add column start_date date;
alter table public.chittis add column end_date date;

update public.chittis
set start_date = first_due_date,
    end_date = (first_due_date + make_interval(months => member_count - 1))::date;

alter table public.chittis alter column start_date set not null;
alter table public.chittis alter column end_date set not null;
alter table public.chittis alter column start_date set default ((now() at time zone 'Asia/Kolkata')::date);
alter table public.chittis alter column end_date set default ((now() at time zone 'Asia/Kolkata')::date);
alter table public.chittis add constraint chittis_due_after_start_check check (first_due_date >= start_date);
alter table public.chittis add constraint chittis_end_after_due_check check (end_date >= first_due_date);

create function public.sync_chitti_schedule()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.end_date := (new.first_due_date + make_interval(months => new.member_count - 1))::date;
  return new;
end;
$$;

create trigger chittis_schedule_sync
before insert or update of member_count, first_due_date
on public.chittis
for each row execute function public.sync_chitti_schedule();

alter table public.rounds add column period_start_date date;
update public.rounds r
set period_start_date = (c.start_date + make_interval(months => r.round_number - 1))::date
from public.chittis c
where c.id = r.chitti_id;
alter table public.rounds alter column period_start_date set not null;
alter table public.rounds alter column period_start_date set default ((now() at time zone 'Asia/Kolkata')::date);
alter table public.rounds add constraint rounds_due_after_period_start_check check (due_date >= period_start_date);

create function public.sync_round_schedule()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_start_date date;
begin
  select start_date into v_start_date
  from public.chittis
  where id = new.chitti_id;

  new.period_start_date := (v_start_date + make_interval(months => new.round_number - 1))::date;
  if tg_op = 'INSERT'
     and new.round_number = 1
     and new.status in ('upcoming', 'collecting') then
    new.status := case
      when new.period_start_date <= (now() at time zone 'Asia/Kolkata')::date
        then 'collecting'::public.round_status
      else 'upcoming'::public.round_status
    end;
  end if;
  return new;
end;
$$;

create trigger rounds_schedule_sync
before insert or update of chitti_id, round_number
on public.rounds
for each row execute function public.sync_round_schedule();

alter table public.contributions add column confirmed_on_time boolean;
alter table public.contributions add column overdue_at timestamptz;

update public.contributions c
set confirmed_on_time = (
  (coalesce(c.submitted_at, c.confirmed_at) at time zone 'Asia/Kolkata')::date <= r.due_date
)
from public.rounds r
where r.id = c.round_id
  and c.status = 'confirmed'
  and coalesce(c.submitted_at, c.confirmed_at) is not null;

update public.contributions c
set overdue_at = coalesce(c.updated_at, now())
from public.rounds r
where r.id = c.round_id
  and (c.status = 'overdue' or (c.status <> 'confirmed' and r.due_date < (now() at time zone 'Asia/Kolkata')::date));

create or replace function public.create_chitti(input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_invite jsonb;
  v_token text;
  v_invitation_id uuid;
  v_links jsonb := '[]'::jsonb;
  v_count int;
  v_first_due date;
  v_start_date date;
begin
  if not public.is_admin() then
    raise exception 'Only the administrator can create a chitti';
  end if;

  v_count := (input->>'memberCount')::int;
  v_first_due := (input->>'firstDueDate')::date;
  v_start_date := coalesce(nullif(input->>'startDate', '')::date, v_first_due);
  if v_first_due < v_start_date then
    raise exception 'The first due date cannot be before the chitti start date';
  end if;
  if jsonb_array_length(input->'invites') <> v_count - 1 then
    raise exception 'Invitation count must equal member count minus one';
  end if;

  insert into public.chittis(
    name,
    description,
    admin_id,
    monthly_amount_paise,
    member_count,
    start_date,
    first_due_date,
    due_day,
    upi_id,
    payee_name,
    status
  ) values (
    input->>'name',
    nullif(input->>'description', ''),
    auth.uid(),
    (input->>'monthlyAmountPaise')::bigint,
    v_count,
    v_start_date,
    v_first_due,
    (input->>'dueDay')::smallint,
    input->>'upiId',
    input->>'payeeName',
    'inviting'
  )
  returning * into v_chitti;

  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position)
  values (v_chitti.id, auth.uid(), true, 1);

  for v_invite in select value from jsonb_array_elements(input->'invites')
  loop
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.invitations(
      chitti_id,
      invited_name,
      invited_email,
      invited_phone,
      token_hash
    ) values (
      v_chitti.id,
      v_invite->>'name',
      lower(v_invite->>'email'),
      v_invite->>'phone',
      extensions.digest(v_token, 'sha256')
    )
    returning id into v_invitation_id;

    v_links := v_links || jsonb_build_array(jsonb_build_object(
      'id', v_invitation_id,
      'name', v_invite->>'name',
      'email', lower(v_invite->>'email'),
      'token', v_token
    ));

    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    select
      id,
      'invitation.created',
      'You have a private Chitti invitation',
      'Open Chitti to review your invitation.',
      '/invite?invitation=' || v_invitation_id,
      'invite:' || v_chitti.id
    from public.profiles
    where lower(email) = lower(v_invite->>'email')
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
  end loop;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(),
    v_chitti.id,
    'chitti.created',
    'chitti',
    v_chitti.id::text,
    jsonb_build_object(
      'start_date', v_chitti.start_date,
      'first_due_date', v_chitti.first_due_date,
      'end_date', v_chitti.end_date
    )
  );

  return jsonb_build_object('chitti_id', v_chitti.id, 'invitations', v_links);
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
  select r.* into v_round
  from public.contributions c
  join public.rounds r on r.id = c.round_id
  where c.id = p_contribution_id;
  v_chitti_id := v_round.chitti_id;

  if not public.is_chitti_admin(v_chitti_id) then
    raise exception 'Administrator access required';
  end if;

  update public.contributions
  set status = case
      when p_accepted then 'confirmed'::public.contribution_status
      else 'rejected'::public.contribution_status
    end,
    reviewed_by = auth.uid(),
    confirmed_at = case when p_accepted then now() else null end,
    confirmed_on_time = case
      when p_accepted then (submitted_at at time zone 'Asia/Kolkata')::date <= v_round.due_date
      else null
    end
  where id = p_contribution_id and status = 'submitted';

  if not found then
    raise exception 'Contribution is not awaiting review';
  end if;

  if p_accepted then
    update public.payout_adjustments
    set status = 'ready'
    where contribution_id = p_contribution_id and status = 'awaiting_contribution'
    returning * into v_adjustment;

    if v_adjustment.id is not null then
      insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
      values (
        v_adjustment.recipient_id,
        'payout.topup_ready',
        'An additional payout is ready',
        'A late member''s catch-up contribution was confirmed.',
        '/chitti/' || v_chitti_id,
        'topup-ready:' || v_adjustment.id
      );
    end if;

    if v_round.status <> 'completed' then
      select count(*) into v_remaining
      from public.contributions
      where round_id = v_round.id and status <> 'confirmed';
      if v_remaining = 0 then
        update public.rounds set status = 'ready_for_payout' where id = v_round.id;
        update public.payouts set status = 'ready' where round_id = v_round.id;
      end if;
    end if;
  end if;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(),
    v_chitti_id,
    'contribution.reviewed',
    'contribution',
    p_contribution_id::text,
    jsonb_build_object(
      'accepted', p_accepted,
      'confirmed_on_time', case
        when p_accepted then (select confirmed_on_time from public.contributions where id = p_contribution_id)
        else null
      end
    )
  );

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select
    member_id,
    'contribution.reviewed',
    case when p_accepted then 'Payment confirmed' else 'Payment needs attention' end,
    case
      when p_accepted then 'The administrator confirmed your contribution.'
      else 'The administrator could not confirm your contribution. Please review it.'
    end,
    '/chitti/' || v_chitti_id,
    'reviewed:' || p_contribution_id || ':' || p_accepted
  from public.contributions
  where id = p_contribution_id
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

create or replace function public.process_due_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  update public.rounds r
  set status = 'collecting'
  where status = 'upcoming'
    and period_start_date <= v_today
    and not exists (
      select 1
      from public.rounds previous
      where previous.chitti_id = r.chitti_id
        and previous.round_number < r.round_number
        and previous.status <> 'completed'
    );

  update public.contributions c
  set status = 'overdue',
      overdue_at = coalesce(overdue_at, now())
  from public.rounds r
  where r.id = c.round_id
    and r.status = 'collecting'
    and r.due_date < v_today
    and c.status = 'due';

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select
    c.member_id,
    case when r.due_date < v_today then 'contribution.overdue' else 'contribution.reminder' end,
    case
      when r.due_date < v_today then 'Chitti payment is overdue'
      when r.due_date = v_today then 'Chitti payment is due today'
      else 'Upcoming Chitti payment'
    end,
    case
      when r.due_date < v_today then 'Your contribution is past due. Open Chitti to submit it.'
      when r.due_date = v_today then 'Your contribution is due today. Open Chitti to submit it.'
      else 'Your contribution is due on ' || to_char(r.due_date, 'DD Mon YYYY') || '.'
    end,
    '/chitti/' || r.chitti_id,
    'payment-reminder:' || c.id || ':' || v_today
  from public.contributions c
  join public.rounds r on r.id = c.round_id
  where r.status = 'collecting'
    and r.period_start_date <= v_today
    and c.status in ('due', 'rejected', 'overdue')
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

create or replace function public.get_app_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_snapshot jsonb;
begin
  v_snapshot := public.get_app_snapshot_without_rejection_reasons();

  return jsonb_set(
    v_snapshot,
    '{chittis}',
    coalesce((
      select jsonb_agg(
        chitti || jsonb_build_object(
          'startDate', c.start_date,
          'endDate', c.end_date,
          'members',
          coalesce((
            select jsonb_agg(
              case
                when public.is_chitti_admin(c.id) or member->>'id' = auth.uid()::text
                then member || jsonb_build_object(
                  'approvalReason',
                  coalesce((
                    select to_jsonb(sa.reason)
                    from public.shuffle_runs sr
                    join public.shuffle_approvals sa on sa.shuffle_run_id = sr.id
                    where sr.chitti_id = c.id
                      and sa.member_id = (member->>'id')::uuid
                    order by sr.run_number desc
                    limit 1
                  ), 'null'::jsonb)
                )
                else member - 'approvalReason'
              end
              order by member_order
            )
            from jsonb_array_elements(chitti->'members') with ordinality as members(member, member_order)
          ), '[]'::jsonb),
          'rounds',
          coalesce((
            select jsonb_agg(
              round_item || jsonb_build_object(
                'periodStartDate', r.period_start_date,
                'contributions',
                coalesce((
                  select jsonb_agg(
                    contribution || jsonb_build_object(
                      'confirmedOnTime', coalesce(to_jsonb(con.confirmed_on_time), 'null'::jsonb),
                      'overdueAt', coalesce(to_jsonb(con.overdue_at), 'null'::jsonb)
                    )
                    order by contribution_order
                  )
                  from jsonb_array_elements(round_item->'contributions') with ordinality as contributions(contribution, contribution_order)
                  join public.contributions con on con.id = (contribution->>'id')::uuid
                ), '[]'::jsonb)
              )
              order by round_order
            )
            from jsonb_array_elements(chitti->'rounds') with ordinality as round_items(round_item, round_order)
            join public.rounds r on r.id = (round_item->>'id')::uuid
          ), '[]'::jsonb)
        )
        order by chitti_order
      )
      from jsonb_array_elements(v_snapshot->'chittis') with ordinality as chittis_json(chitti, chitti_order)
      join public.chittis c on c.id = (chitti->>'id')::uuid
    ), '[]'::jsonb),
    true
  );
end;
$$;

revoke all on function public.create_chitti(jsonb) from public, anon;
grant execute on function public.create_chitti(jsonb) to authenticated;
revoke all on function public.review_contribution(uuid, boolean) from public, anon;
grant execute on function public.review_contribution(uuid, boolean) to authenticated;
revoke all on function public.process_due_reminders() from public, anon, authenticated;
grant execute on function public.process_due_reminders() to service_role;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

commit;
