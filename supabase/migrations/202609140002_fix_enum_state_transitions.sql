-- CASE expressions containing only string literals resolve to text in PostgreSQL.
-- Explicit enum casts keep shuffle voting and payment review type-safe.

create or replace function public.respond_to_shuffle(p_chitti_id uuid, p_accepted boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.shuffle_runs;
  v_pending int;
  v_assignment record;
  v_round_id uuid;
begin
  if not public.is_chitti_member(p_chitti_id) then
    raise exception 'Membership required';
  end if;

  select * into v_run
  from public.shuffle_runs
  where chitti_id = p_chitti_id and status = 'revealed'
  order by run_number desc
  limit 1
  for update;

  if v_run.id is null then
    raise exception 'No active shuffle approval';
  end if;

  update public.shuffle_approvals
  set status = case
      when p_accepted then 'accepted'::public.approval_status
      else 'rejected'::public.approval_status
    end,
    reason = p_reason,
    responded_at = now()
  where shuffle_run_id = v_run.id
    and member_id = auth.uid()
    and status = 'pending';

  if not found then
    raise exception 'Approval already recorded';
  end if;

  if not p_accepted then
    update public.shuffle_runs set status = 'rejected' where id = v_run.id;
    update public.chittis set status = 'ready' where id = p_chitti_id;
    insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
    values (auth.uid(), p_chitti_id, 'shuffle.rejected', 'shuffle_run', v_run.id::text, jsonb_build_object('reason', p_reason));
    perform public.notify_chitti_members(p_chitti_id, 'shuffle.rejected', 'Payout order was not accepted',
      'The administrator will discuss the result before scheduling another shuffle.', '/chitti/' || p_chitti_id,
      v_run.id::text, null);
    return;
  end if;

  select count(*) into v_pending
  from public.shuffle_approvals
  where shuffle_run_id = v_run.id and status <> 'accepted';

  if v_pending = 0 then
    update public.chitti_members m
    set payout_position = a.payout_position
    from public.shuffle_assignments a
    where a.shuffle_run_id = v_run.id
      and m.chitti_id = p_chitti_id
      and m.user_id = a.member_id;

    update public.shuffle_runs set status = 'locked', locked_at = now() where id = v_run.id;
    update public.chittis set status = 'active', locked_at = now() where id = p_chitti_id;

    for v_assignment in
      select * from public.shuffle_assignments
      where shuffle_run_id = v_run.id
      order by payout_position
    loop
      insert into public.rounds(chitti_id, round_number, due_date, recipient_id, status)
      select p_chitti_id,
        v_assignment.payout_position,
        (first_due_date + make_interval(months => v_assignment.payout_position - 1))::date,
        v_assignment.member_id,
        case
          when v_assignment.payout_position = 1
            and first_due_date <= (now() at time zone 'Asia/Kolkata')::date
            then 'collecting'::public.round_status
          else 'upcoming'::public.round_status
        end
      from public.chittis
      where id = p_chitti_id
      returning id into v_round_id;

      insert into public.contributions(round_id, member_id)
      select v_round_id, user_id from public.chitti_members where chitti_id = p_chitti_id;
      insert into public.payouts(round_id) values (v_round_id);
    end loop;

    insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id)
    values (auth.uid(), p_chitti_id, 'shuffle.locked', 'shuffle_run', v_run.id::text);
    perform public.notify_chitti_members(p_chitti_id, 'chitti.activated', 'Payout order locked',
      'Everyone agreed. Monthly contribution tracking is now active.', '/chitti/' || p_chitti_id,
      v_run.id::text, null);
  end if;
end;
$$;

create or replace function public.review_contribution(p_contribution_id uuid, p_accepted boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round_id uuid;
  v_chitti_id uuid;
  v_remaining int;
begin
  select c.round_id, r.chitti_id
  into v_round_id, v_chitti_id
  from public.contributions c
  join public.rounds r on r.id = c.round_id
  where c.id = p_contribution_id;

  if not public.is_chitti_admin(v_chitti_id) then
    raise exception 'Administrator access required';
  end if;

  update public.contributions
  set status = case
      when p_accepted then 'confirmed'::public.contribution_status
      else 'rejected'::public.contribution_status
    end,
    reviewed_by = auth.uid(),
    confirmed_at = case when p_accepted then now() else null end
  where id = p_contribution_id and status = 'submitted';

  if not found then
    raise exception 'Contribution is not awaiting review';
  end if;

  if p_accepted then
    select count(*) into v_remaining
    from public.contributions
    where round_id = v_round_id and status <> 'confirmed';
    if v_remaining = 0 then
      update public.rounds set status = 'ready_for_payout' where id = v_round_id;
      update public.payouts set status = 'ready' where round_id = v_round_id;
    end if;
  end if;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), v_chitti_id, 'contribution.reviewed', 'contribution', p_contribution_id::text,
    jsonb_build_object('accepted', p_accepted));

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select member_id,
    'contribution.reviewed',
    case when p_accepted then 'Payment confirmed' else 'Payment needs attention' end,
    case when p_accepted then 'The administrator confirmed your contribution.'
      else 'The administrator could not confirm your contribution. Please review it.' end,
    '/chitti/' || v_chitti_id,
    'reviewed:' || p_contribution_id || ':' || p_accepted
  from public.contributions
  where id = p_contribution_id
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end;
$$;

revoke all on function public.respond_to_shuffle(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_shuffle(uuid, boolean, text) to authenticated;
revoke all on function public.review_contribution(uuid, boolean) from public, anon;
grant execute on function public.review_contribution(uuid, boolean) to authenticated;
