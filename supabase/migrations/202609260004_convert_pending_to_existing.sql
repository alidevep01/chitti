begin;

create function public.convert_pending_chitti_to_existing(
  p_chitti_id uuid,
  p_completed_months smallint,
  p_order jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_admin_member public.chitti_members;
  v_item jsonb;
  v_position int := 2;
  v_expected int;
  v_seen text[] := array[]::text[];
begin
  select * into v_chitti from public.chittis where id = p_chitti_id for update;
  if v_chitti.id is null or not public.is_chitti_admin(p_chitti_id) then
    raise exception 'Administrator access required';
  end if;
  if v_chitti.status not in ('draft', 'inviting', 'ready', 'shuffle_scheduled', 'awaiting_approval') then
    raise exception 'Only a pending chitti can be changed to an existing chitti';
  end if;
  if v_chitti.is_imported then raise exception 'This is already an existing chitti'; end if;
  if p_completed_months not between 0 and v_chitti.member_count then
    raise exception 'Completed months must be between zero and the total months';
  end if;

  select * into v_admin_member from public.chitti_members
  where chitti_id = p_chitti_id and user_id = v_chitti.admin_id;
  if v_admin_member.user_id is null then raise exception 'Administrator membership is missing'; end if;
  update public.chitti_members set payout_position = 1
  where chitti_id = p_chitti_id and user_id = v_chitti.admin_id;

  select count(*) into v_expected
  from (
    select 'member:' || member.user_id::text key
    from public.chitti_members member
    where member.chitti_id = p_chitti_id and member.user_id <> v_chitti.admin_id
    union all
    select 'invitation:' || invitation.id::text
    from public.invitations invitation
    where invitation.chitti_id = p_chitti_id and invitation.status = 'pending'
  ) participants;
  if v_expected > v_chitti.member_count - 1 then
    raise exception 'The chitti has more participants than available payout positions';
  end if;
  if jsonb_typeof(p_order) <> 'array' or jsonb_array_length(p_order) <> v_expected then
    raise exception 'Arrange every currently added member and invitation exactly once';
  end if;

  update public.chitti_members set payout_position = null
  where chitti_id = p_chitti_id and user_id <> v_chitti.admin_id;
  update public.invitations set payout_position = null
  where chitti_id = p_chitti_id and status = 'pending';

  for v_item in select value from jsonb_array_elements(p_order)
  loop
    if (v_item->>'kind') not in ('member', 'invitation') then raise exception 'Invalid payout-order item'; end if;
    if (v_item->>'id') is null then raise exception 'Payout-order item is missing an ID'; end if;
    if ((v_item->>'kind') || ':' || (v_item->>'id')) = any(v_seen) then raise exception 'A payout-order item was repeated'; end if;
    v_seen := array_append(v_seen, (v_item->>'kind') || ':' || (v_item->>'id'));

    if v_item->>'kind' = 'member' then
      update public.chitti_members set payout_position = v_position
      where chitti_id = p_chitti_id and user_id = (v_item->>'id')::uuid and user_id <> v_chitti.admin_id;
    else
      update public.invitations set payout_position = v_position
      where chitti_id = p_chitti_id and id = (v_item->>'id')::uuid and status = 'pending';
    end if;
    if not found then raise exception 'A payout-order participant is unavailable'; end if;
    v_position := v_position + 1;
  end loop;

  delete from public.shuffle_approvals approval using public.shuffle_runs run
  where approval.shuffle_run_id = run.id and run.chitti_id = p_chitti_id;
  delete from public.shuffle_assignments assignment using public.shuffle_runs run
  where assignment.shuffle_run_id = run.id and run.chitti_id = p_chitti_id;
  delete from public.shuffle_runs where chitti_id = p_chitti_id;

  update public.chittis
  set is_imported = true,
      imported_completed_months = p_completed_months,
      status = 'inviting',
      shuffle_scheduled_at = null,
      locked_at = null
  where id = p_chitti_id;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), p_chitti_id, 'chitti.converted_to_existing', 'chitti', p_chitti_id::text,
    jsonb_build_object('completed_months', p_completed_months, 'manual_order', p_order));

  perform public.notify_chitti_members(
    p_chitti_id,
    'chitti.converted_to_existing',
    'Saved payout order added',
    'The administrator marked this as an existing chitti and recorded its established payout order.',
    '/chitti/' || p_chitti_id,
    p_chitti_id::text,
    auth.uid()
  );
  perform public.activate_imported_chitti(p_chitti_id);
end;
$$;

revoke all on function public.convert_pending_chitti_to_existing(uuid, smallint, jsonb) from public, anon;
grant execute on function public.convert_pending_chitti_to_existing(uuid, smallint, jsonb) to authenticated;

commit;
