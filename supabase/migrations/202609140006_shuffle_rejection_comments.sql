begin;

drop policy if exists shuffle_approvals_member_select on public.shuffle_approvals;
create policy shuffle_approvals_private_select
on public.shuffle_approvals
for select
to authenticated
using (
  member_id = auth.uid()
  or exists (
    select 1
    from public.shuffle_runs sr
    where sr.id = shuffle_approvals.shuffle_run_id
      and public.is_chitti_admin(sr.chitti_id)
  )
);

create or replace function public.respond_to_shuffle(
  p_chitti_id uuid,
  p_accepted boolean,
  p_reason text default null
)
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
  v_admin_id uuid;
  v_rejector_name text;
  v_reason text;
begin
  if not public.is_chitti_member(p_chitti_id) then
    raise exception 'Membership required';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if not p_accepted and coalesce(char_length(v_reason), 0) < 3 then
    raise exception 'Please explain why you want a reshuffle';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'The reshuffle comment must be 500 characters or fewer';
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
    reason = case when p_accepted then null else v_reason end,
    responded_at = now()
  where shuffle_run_id = v_run.id
    and member_id = auth.uid()
    and status = 'pending';

  if not found then
    raise exception 'Approval already recorded';
  end if;

  if not p_accepted then
    select c.admin_id, p.display_name
    into v_admin_id, v_rejector_name
    from public.chittis c
    join public.profiles p on p.id = auth.uid()
    where c.id = p_chitti_id;

    update public.shuffle_runs
    set status = 'rejected'
    where id = v_run.id;
    update public.chittis
    set status = 'ready'
    where id = p_chitti_id;

    insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
    values (
      auth.uid(),
      p_chitti_id,
      'shuffle.rejected',
      'shuffle_run',
      v_run.id::text,
      jsonb_build_object('reason', v_reason)
    );

    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    values (
      v_admin_id,
      'shuffle.rejected.admin',
      v_rejector_name || ' requested a reshuffle',
      v_reason,
      '/chitti/' || p_chitti_id || '/shuffle',
      'shuffle-rejected-admin:' || v_run.id
    )
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

    perform public.notify_chitti_members(
      p_chitti_id,
      'shuffle.rejected',
      'A reshuffle was requested',
      'The administrator will review the request before scheduling another shuffle.',
      '/chitti/' || p_chitti_id,
      v_run.id::text,
      v_admin_id
    );
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

    update public.shuffle_runs
    set status = 'locked', locked_at = now()
    where id = v_run.id;
    update public.chittis
    set status = 'active', locked_at = now()
    where id = p_chitti_id;

    for v_assignment in
      select *
      from public.shuffle_assignments
      where shuffle_run_id = v_run.id
      order by payout_position
    loop
      insert into public.rounds(chitti_id, round_number, due_date, recipient_id, status)
      select
        p_chitti_id,
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
      select v_round_id, user_id
      from public.chitti_members
      where chitti_id = p_chitti_id;
      insert into public.payouts(round_id) values (v_round_id);
    end loop;

    insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id)
    values (auth.uid(), p_chitti_id, 'shuffle.locked', 'shuffle_run', v_run.id::text);
    perform public.notify_chitti_members(
      p_chitti_id,
      'chitti.activated',
      'Payout order locked',
      'Everyone agreed. Monthly contribution tracking is now active.',
      '/chitti/' || p_chitti_id,
      v_run.id::text,
      null
    );
  end if;
end;
$$;

alter function public.get_app_snapshot() rename to get_app_snapshot_without_rejection_reasons;

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
  v_snapshot := public.get_app_snapshot_without_rejection_reasons();

  return jsonb_set(
    v_snapshot,
    '{chittis}',
    coalesce((
      select jsonb_agg(
        chitti || jsonb_build_object(
          'members',
          coalesce((
            select jsonb_agg(
              case
                when public.is_chitti_admin((chitti->>'id')::uuid)
                  or member->>'id' = auth.uid()::text
                then member || jsonb_build_object(
                  'approvalReason',
                  coalesce((
                    select to_jsonb(sa.reason)
                    from public.shuffle_runs sr
                    join public.shuffle_approvals sa on sa.shuffle_run_id = sr.id
                    where sr.chitti_id = (chitti->>'id')::uuid
                      and sa.member_id = (member->>'id')::uuid
                    order by sr.run_number desc
                    limit 1
                  ), 'null'::jsonb)
                )
                else member - 'approvalReason'
              end
            )
            from jsonb_array_elements(chitti->'members') member
          ), '[]'::jsonb)
        )
      )
      from jsonb_array_elements(v_snapshot->'chittis') chitti
    ), '[]'::jsonb),
    true
  );
end;
$$;

revoke all on function public.respond_to_shuffle(uuid, boolean, text) from public, anon;
grant execute on function public.respond_to_shuffle(uuid, boolean, text) to authenticated;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

commit;
