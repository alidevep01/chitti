begin;

alter table public.chitti_members
  drop constraint chitti_members_chitti_id_payout_position_key;
alter table public.chitti_members
  add constraint chitti_members_chitti_id_payout_position_key
  unique (chitti_id, payout_position) deferrable initially immediate;

alter table public.rounds
  drop constraint rounds_chitti_id_recipient_id_key;
alter table public.rounds
  add constraint rounds_chitti_id_recipient_id_key
  unique (chitti_id, recipient_id) deferrable initially immediate;

create or replace function public.swap_payout_months(
  p_chitti_id uuid,
  p_first_member_id uuid,
  p_second_member_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_first public.chitti_members;
  v_second public.chitti_members;
  v_first_date date;
  v_second_date date;
begin
  if p_first_member_id = p_second_member_id then
    raise exception 'Choose two different members';
  end if;

  select * into v_chitti
  from public.chittis
  where id = p_chitti_id
  for update;

  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if v_chitti.status <> 'active' then
    raise exception 'Payout months can be swapped only for an active chitti';
  end if;

  select * into v_first
  from public.chitti_members
  where chitti_id = p_chitti_id and user_id = p_first_member_id;
  select * into v_second
  from public.chitti_members
  where chitti_id = p_chitti_id and user_id = p_second_member_id;

  if v_first.user_id is null or v_second.user_id is null then
    raise exception 'Both members must belong to this chitti';
  end if;
  if v_first.is_admin or v_second.is_admin then
    raise exception 'The administrator must remain in payout month 1';
  end if;
  if v_first.payout_position is null or v_second.payout_position is null then
    raise exception 'Both payout months must be assigned';
  end if;
  if exists(
    select 1
    from public.rounds r
    join public.payouts p on p.round_id = r.id
    where r.chitti_id = p_chitti_id
      and r.round_number in (v_first.payout_position, v_second.payout_position)
      and (r.status = 'completed' or p.status = 'paid')
  ) then
    raise exception 'Completed or paid payout months cannot be changed';
  end if;

  set constraints public.chitti_members_chitti_id_payout_position_key deferred;
  set constraints public.rounds_chitti_id_recipient_id_key deferred;

  update public.chitti_members
  set payout_position = case
    when user_id = p_first_member_id then v_second.payout_position
    when user_id = p_second_member_id then v_first.payout_position
  end
  where chitti_id = p_chitti_id
    and user_id in (p_first_member_id, p_second_member_id);

  update public.rounds
  set recipient_id = case
    when round_number = v_first.payout_position then p_second_member_id
    when round_number = v_second.payout_position then p_first_member_id
  end
  where chitti_id = p_chitti_id
    and round_number in (v_first.payout_position, v_second.payout_position);

  select due_date into v_first_date
  from public.rounds
  where chitti_id = p_chitti_id and round_number = v_second.payout_position;
  select due_date into v_second_date
  from public.rounds
  where chitti_id = p_chitti_id and round_number = v_first.payout_position;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  values
    (
      p_first_member_id,
      'payout.month_changed',
      'Your payout month changed',
      'The administrator moved your payout to month ' || v_second.payout_position ||
        ' (' || to_char(v_first_date, 'DD Mon YYYY') || ').',
      '/chitti/' || p_chitti_id,
      'month-swap:' || p_chitti_id || ':' || p_first_member_id || ':' || now()
    ),
    (
      p_second_member_id,
      'payout.month_changed',
      'Your payout month changed',
      'The administrator moved your payout to month ' || v_first.payout_position ||
        ' (' || to_char(v_second_date, 'DD Mon YYYY') || ').',
      '/chitti/' || p_chitti_id,
      'month-swap:' || p_chitti_id || ':' || p_second_member_id || ':' || now()
    );

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(),
    p_chitti_id,
    'payout.months_swapped',
    'chitti',
    p_chitti_id::text,
    jsonb_build_object(
      'first_member', p_first_member_id,
      'first_old_month', v_first.payout_position,
      'first_new_month', v_second.payout_position,
      'second_member', p_second_member_id,
      'second_old_month', v_second.payout_position,
      'second_new_month', v_first.payout_position
    )
  );

  set constraints public.chitti_members_chitti_id_payout_position_key immediate;
  set constraints public.rounds_chitti_id_recipient_id_key immediate;
end;
$$;

revoke all on function public.swap_payout_months(uuid, uuid, uuid) from public, anon;
grant execute on function public.swap_payout_months(uuid, uuid, uuid) to authenticated;

commit;
