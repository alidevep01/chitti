begin;

create function public.combine_existing_members(
  p_chitti_id uuid, p_keep_kind text, p_keep_id uuid, p_move_kind text, p_move_id uuid,
  p_move_amount_paise bigint, p_expected_count integer, p_keep_position integer, p_move_position integer
) returns void language plpgsql security definer set search_path = '' as $$
declare c public.chittis; k record; m record; occupants integer; remainder bigint; invite_positions jsonb;
begin
  select * into c from public.chittis where id = p_chitti_id for update;
  if c.id is null or not public.is_chitti_admin(c.id) then raise exception 'Administrator access required'; end if;
  if not c.is_imported or c.status <> 'inviting' or c.locked_at is not null
    or c.imported_completed_months <> 0 or exists(select 1 from public.rounds where chitti_id = c.id) then
    raise exception 'Combine only in a pending existing chitti with no completed months or payment history';
  end if;
  if c.member_count <= 2 then raise exception 'At least two payout positions must remain'; end if;
  if p_keep_kind is null or p_move_kind is null or p_keep_kind not in ('member','invitation') or p_move_kind not in ('member','invitation') then raise exception 'Invalid participant type'; end if;
  select * into k from (
    select 'member' kind, user_id id, payout_position position, contribution_amount_paise amount from public.chitti_members where chitti_id = c.id
    union all select 'invitation', id, payout_position, c.monthly_amount_paise from public.invitations where chitti_id = c.id and status = 'pending'
  ) roster where kind = p_keep_kind and id = p_keep_id;
  select * into m from (
    select 'member' kind, user_id id, payout_position position, contribution_amount_paise amount from public.chitti_members where chitti_id = c.id
    union all select 'invitation', id, payout_position, c.monthly_amount_paise from public.invitations where chitti_id = c.id and status = 'pending'
  ) roster where kind = p_move_kind and id = p_move_id;
  if k.id is null or m.id is null or k.position is null or m.position is null or k.position = m.position
    or m.position = 1 or k.position not between 1 and c.member_count or m.position not between 2 and c.member_count then
    raise exception 'Choose two separate full positions; keep the administrator at position 1';
  end if;
  if c.member_count is distinct from p_expected_count or k.position is distinct from p_keep_position or m.position is distinct from p_move_position then
    raise exception 'The roster changed. Close and reopen Combine existing members';
  end if;
  select count(*) into occupants from (
    select payout_position from public.chitti_members where chitti_id = c.id
    union all select payout_position from public.invitations where chitti_id = c.id and status = 'pending'
  ) roster where payout_position in (k.position, m.position);
  if occupants <> 2 or k.amount <> c.monthly_amount_paise or m.amount <> c.monthly_amount_paise
    or exists(select 1 from public.invitations where chitti_id = c.id and status = 'pending'
      and payout_position in (k.position,m.position) and coowner_share_bps is not null) then
    raise exception 'Choose full positions that do not already have co-owners or reserved shares';
  end if;
  if p_move_amount_paise is null or p_move_amount_paise <= 0 or p_move_amount_paise >= c.monthly_amount_paise then raise exception 'Both owners must have a positive monthly amount'; end if;
  remainder := c.monthly_amount_paise - p_move_amount_paise;
  if p_keep_kind = 'member' and p_move_kind = 'member' then
    update public.chitti_members set contribution_amount_paise = case when user_id = p_move_id then p_move_amount_paise else remainder end,
      contribution_share_bps = greatest(1, floor((case when user_id = p_move_id then p_move_amount_paise else remainder end) * 10000.0 / c.monthly_amount_paise))
    where chitti_id = c.id and user_id in (p_keep_id,p_move_id);
    update public.invitations set coowner_source_member_id = p_keep_id, coowner_source_invitation_id = null,
      coowner_amount_paise = p_move_amount_paise, coowner_share_bps = greatest(1, floor(p_move_amount_paise * 10000.0 / c.monthly_amount_paise))
    where chitti_id = c.id and status = 'accepted' and accepted_by = p_move_id;
  elsif p_move_kind = 'invitation' then
    update public.invitations set coowner_amount_paise = p_move_amount_paise,
      coowner_share_bps = greatest(1, floor(p_move_amount_paise * 10000.0 / c.monthly_amount_paise)),
      coowner_source_member_id = case when p_keep_kind = 'member' then p_keep_id end,
      coowner_source_invitation_id = case when p_keep_kind = 'invitation' then p_keep_id end
    where id = p_move_id;
  else
    update public.invitations set coowner_amount_paise = remainder,
      coowner_share_bps = greatest(1, floor(remainder * 10000.0 / c.monthly_amount_paise)), coowner_source_member_id = p_move_id
    where id = p_keep_id;
  end if;
  -- Move the owners together and close the freed gap, including accepted invite metadata.
  update public.chitti_members set payout_position =
    (case when payout_position = m.position then k.position else payout_position end)
    - case when (case when payout_position = m.position then k.position else payout_position end) > m.position then 1 else 0 end
  where chitti_id = c.id;
  select jsonb_object_agg(id::text,payout_position) into invite_positions from public.invitations
    where chitti_id = c.id and status in ('pending','accepted');
  -- Clear first to avoid transient collisions with the partial unique invitation index.
  update public.invitations set payout_position = null where chitti_id = c.id and status in ('pending','accepted');
  update public.invitations i set payout_position =
    (case when (invite_positions->>i.id::text)::int = m.position then k.position else (invite_positions->>i.id::text)::int end)
    - case when (case when (invite_positions->>i.id::text)::int = m.position then k.position else (invite_positions->>i.id::text)::int end) > m.position then 1 else 0 end
  where i.chitti_id = c.id and i.status in ('pending','accepted');
  update public.chittis set member_count = member_count - 1 where id = c.id;
  insert into public.audit_events(actor_id,chitti_id,action,entity_type,entity_id,detail)
  values(auth.uid(),c.id,'chitti.members_combined','chitti',c.id::text,jsonb_build_object(
    'keep_kind',p_keep_kind,'keep_id',p_keep_id,'move_kind',p_move_kind,'move_id',p_move_id,
    'keep_amount_paise',remainder,'move_amount_paise',p_move_amount_paise,'old_keep_position',k.position,
    'removed_position',m.position,'old_months',c.member_count,'new_months',c.member_count-1));
  perform public.notify_chitti_members(c.id,'chitti.members_combined','Shared position updated',
    'The administrator combined two positions. Review your amount, ranking and the shorter schedule.', '/chitti/' || c.id,gen_random_uuid()::text,null);
  perform public.activate_imported_chitti(c.id);
end;
$$;
revoke all on function public.combine_existing_members(uuid,text,uuid,text,uuid,bigint,integer,integer,integer) from public,anon;
grant execute on function public.combine_existing_members(uuid,text,uuid,text,uuid,bigint,integer,integer,integer) to authenticated;

-- A joined pair need not have invitation rows (for example, imported admin records).
-- Route those shared ranks through the existing group-aware ranking editor too.
do $$
declare definition text; previous text := 'if not exists(select 1 from public.invitations where chitti_id = c.id and status in (''pending'', ''accepted'') and coowner_share_bps is not null) then';
begin
  definition := pg_get_functiondef('public.convert_pending_chitti_to_existing(uuid,smallint,jsonb)'::regprocedure);
  if position(previous in definition) = 0 then raise exception 'Unexpected ranking function; review the combine migration before applying'; end if;
  definition := replace(definition, previous,
    'if not exists(select 1 from public.chitti_members where chitti_id = c.id group by payout_position having count(*) > 1) and not exists(select 1 from public.invitations where chitti_id = c.id and status in (''pending'', ''accepted'') and coowner_share_bps is not null) then');
  execute definition;
end;
$$;
commit;
