begin;

alter table public.invitations add column coowner_source_invitation_id uuid
  references public.invitations(id) on delete restrict;
alter table public.invitations drop constraint invitations_coowner_share_check;
alter table public.invitations add constraint invitations_coowner_share_check check (
  (coowner_source_member_id is null and coowner_source_invitation_id is null and coowner_share_bps is null)
  or (num_nonnulls(coowner_source_member_id, coowner_source_invitation_id) = 1
      and coowner_share_bps is not null and coowner_share_bps between 1 and 9999)
);
alter table public.invitations drop constraint invitations_payout_position_check;
alter table public.invitations add constraint invitations_payout_position_check check (
  payout_position is null or payout_position between 2 and 50
  or (payout_position = 1 and coowner_share_bps is not null)
);
drop index public.invitations_chitti_payout_position_idx;
create unique index invitations_chitti_payout_position_idx on public.invitations(chitti_id, payout_position)
  where payout_position is not null and status in ('pending', 'accepted')
    and coowner_source_member_id is null and coowner_source_invitation_id is null;

alter function public.add_coowner_invitation(uuid, uuid, smallint, text, text, text)
  rename to add_coowner_invitation_active;
revoke all on function public.add_coowner_invitation_active(uuid, uuid, smallint, text, text, text) from public, anon, authenticated;

create function public.add_coowner_invitation(
  p_chitti_id uuid, p_source_member_id uuid, p_share_bps smallint,
  p_name text, p_email text, p_phone text, p_source_invitation_id uuid default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  c public.chittis;
  source public.chitti_members;
  source_invite public.invitations;
  position smallint;
  available int;
  reserved int;
  owners int;
  token text;
  invitation_id uuid;
begin
  select * into c from public.chittis where id = p_chitti_id for update;
  if c.id is null or not public.is_chitti_admin(p_chitti_id) then raise exception 'Administrator access required'; end if;
  if c.status <> 'active' and not (c.is_imported and c.status = 'inviting' and c.locked_at is null
      and not exists(select 1 from public.rounds where chitti_id = c.id)) then
    raise exception 'Share a position in a pending existing chitti or an active chitti';
  end if;
  if num_nonnulls(p_source_member_id, p_source_invitation_id) <> 1 then raise exception 'Choose one main owner'; end if;
  if p_source_member_id is not null then
    select * into source from public.chitti_members where chitti_id = c.id and user_id = p_source_member_id;
    position := source.payout_position;
    available := source.contribution_share_bps;
    -- Children invited before this main owner joined still reserve a portion of their share.
    select coalesce(sum(i.coowner_share_bps), 0) into reserved from public.invitations i
    left join public.invitations parent on parent.id = i.coowner_source_invitation_id
    where i.chitti_id = c.id and i.status = 'pending'
      and (i.coowner_source_member_id = source.user_id or parent.accepted_by = source.user_id);
  else
    select * into source_invite from public.invitations where id = p_source_invitation_id and chitti_id = c.id;
    if c.status <> 'inviting' or source_invite.status is distinct from 'pending'
       or source_invite.coowner_source_member_id is not null or source_invite.coowner_source_invitation_id is not null then
      raise exception 'Choose a pending main-owner invitation';
    end if;
    position := source_invite.payout_position;
    available := 10000;
    select coalesce(sum(coowner_share_bps), 0) into reserved from public.invitations
    where coowner_source_invitation_id = source_invite.id and status in ('pending', 'accepted');
  end if;
  available := available - reserved;
  if position is null then raise exception 'Choose an owner with an assigned payout month'; end if;
  if p_share_bps is null or p_share_bps < 1 or p_share_bps >= available then
    raise exception 'The new share must be smaller than the main owner''s unreserved share';
  end if;
  if floor(c.monthly_amount_paise * p_share_bps / 10000.0) < 1
     or floor(c.monthly_amount_paise * (available - p_share_bps) / 10000.0) < 1 then
    raise exception 'Each owner must contribute at least one paise';
  end if;
  select (select count(*) from public.chitti_members where chitti_id = c.id and payout_position = position)
    + (select count(*) from public.invitations i left join public.chitti_members m
        on m.chitti_id = i.chitti_id and m.user_id = i.coowner_source_member_id
        where i.chitti_id = c.id and i.status = 'pending' and coalesce(i.payout_position, m.payout_position) = position)
    into owners;
  if owners >= 3 then raise exception 'A payout position can have at most three owners'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 80 then raise exception 'Enter a valid member name'; end if;
  if p_email is null or position('@' in p_email) < 2 then raise exception 'Enter a valid email address'; end if;
  if p_phone is null or char_length(btrim(p_phone)) < 8 then raise exception 'Enter a valid phone number'; end if;
  if exists(select 1 from public.chitti_members m join public.profiles p on p.id = m.user_id
      where m.chitti_id = c.id and lower(p.email) = lower(btrim(p_email)))
    or exists(select 1 from public.invitations where chitti_id = c.id and status = 'pending' and lower(invited_email) = lower(btrim(p_email))) then
    raise exception 'This email is already a member or has a pending invitation';
  end if;
  if c.status = 'active' then
    return public.add_coowner_invitation_active(c.id, p_source_member_id, p_share_bps, p_name, p_email, p_phone);
  end if;
  token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash,
    payout_position, coowner_source_member_id, coowner_source_invitation_id, coowner_share_bps)
  values (c.id, btrim(p_name), lower(btrim(p_email)), btrim(p_phone), extensions.digest(token, 'sha256'),
    position, p_source_member_id, p_source_invitation_id, p_share_bps) returning id into invitation_id;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select id, 'invitation.coowner_created', 'You have a shared Chitti invitation',
    'You were invited to share payout month ' || position || ' with a ' || (p_share_bps / 100.0) || '% share.',
    '/invite?invitation=' || invitation_id, 'invite:' || invitation_id
  from public.profiles where lower(email) = lower(btrim(p_email))
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), c.id, 'invitation.coowner_added', 'invitation', invitation_id::text,
    jsonb_build_object('payout_position', position, 'share_bps', p_share_bps,
      'source_member_id', p_source_member_id, 'source_invitation_id', p_source_invitation_id));
  return jsonb_build_object('invitation_id', invitation_id, 'token', token, 'payout_position', position, 'share_bps', p_share_bps);
end;
$$;

alter function public.redeem_invitation(text, uuid) rename to redeem_invitation_before_pending_shares;
revoke all on function public.redeem_invitation_before_pending_shares(text, uuid) from public, anon, authenticated;

create function public.redeem_invitation(p_token text default null, p_invitation_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  i public.invitations;
  c public.chittis;
  parent public.invitations;
  source public.chitti_members;
  source_id uuid;
  share int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into i from public.invitations
  where (p_token is not null and token_hash = extensions.digest(p_token, 'sha256')) or (p_invitation_id is not null and id = p_invitation_id);
  select * into c from public.chittis where id = i.chitti_id for update;
  if not coalesce(c.is_imported and c.status in ('inviting', 'ready'), false) then
    return public.redeem_invitation_before_pending_shares(p_token, p_invitation_id);
  end if;
  select * into i from public.invitations where id = i.id for update;
  if i.id is null or i.status <> 'pending' or i.expires_at < now() then raise exception 'Invitation is invalid or expired'; end if;
  if lower(i.invited_email) <> lower(coalesce(auth.jwt()->>'email', '')) then raise exception 'Sign in with the invited Google email'; end if;
  if c.locked_at is not null or exists(select 1 from public.rounds where chitti_id = c.id) then raise exception 'This existing chitti has already activated'; end if;
  if i.payout_position is null or i.payout_position not between 1 and c.member_count then raise exception 'The invitation needs a valid payout position'; end if;
  if i.coowner_share_bps is not null then
    source_id := i.coowner_source_member_id;
    if i.coowner_source_invitation_id is not null then
      select * into parent from public.invitations where id = i.coowner_source_invitation_id and chitti_id = c.id;
      if parent.status not in ('pending', 'accepted') or parent.id is null then raise exception 'The main-owner invitation is unavailable'; end if;
      source_id := parent.accepted_by;
    end if;
    share := i.coowner_share_bps;
    if source_id is not null then
      select * into source from public.chitti_members where chitti_id = c.id and user_id = source_id for update;
      if source.user_id is null or source.payout_position <> i.payout_position or source.contribution_share_bps <= share then
        raise exception 'The shared payout is no longer available';
      end if;
      update public.chitti_members set contribution_share_bps = contribution_share_bps - share
      where chitti_id = c.id and user_id = source_id;
    else
      if share + (select coalesce(sum(coowner_share_bps), 0) from public.invitations
          where coowner_source_invitation_id = parent.id and status = 'accepted') >= 10000 then
        raise exception 'The shared payout is no longer available';
      end if;
    end if;
  else
    -- A co-owner may accept first; reserve their accepted share before the main owner joins.
    select 10000 - coalesce(sum(coowner_share_bps), 0) into share from public.invitations
    where coowner_source_invitation_id = i.id and status = 'accepted';
  end if;
  update public.profiles set phone = case when btrim(phone) = '' then i.invited_phone else phone end where id = auth.uid();
  insert into public.chitti_members(chitti_id, user_id, payout_position, contribution_share_bps)
  values (c.id, auth.uid(), i.payout_position, share);
  update public.invitations set status = 'accepted', accepted_by = auth.uid(), accepted_at = now() where id = i.id;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  values (c.admin_id, 'invitation.accepted', i.invited_name || ' joined',
    case when i.coowner_share_bps is not null then 'A co-owner accepted the shared payout invitation.' else 'A member accepted the invitation.' end,
    '/chitti/' || c.id, 'joined:' || i.id);
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), c.id, 'invitation.accepted', 'invitation', i.id::text,
    jsonb_build_object('payout_position', i.payout_position, 'share_bps', share));
  if source_id is not null then
    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    values (source_id, 'payout.share_changed', 'Your Chitti share changed',
      i.invited_name || ' joined your shared payout position. Open Chitti to review your contribution and share.',
      '/chitti/' || c.id, 'share-changed:' || i.id);
  end if;
  return c.id;
end;
$$;

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
    where (select coalesce(sum(contribution_share_bps), 0) from public.chitti_members where chitti_id = c.id and payout_position = slot.position) <> 10000) then
    raise exception 'Every payout position must have owners with shares totaling 100 percent';
  end if;
  insert into public.rounds(chitti_id, round_number, due_date, recipient_id, status)
  select c.id, m.payout_position, (c.first_due_date + make_interval(months => m.payout_position - 1))::date, m.user_id,
    case when m.payout_position <= c.imported_completed_months then 'completed'::public.round_status
      when m.payout_position = c.imported_completed_months + 1 then 'collecting'::public.round_status else 'upcoming'::public.round_status end
  from (select distinct on (payout_position) * from public.chitti_members where chitti_id = c.id
    order by payout_position, is_admin desc, joined_at, user_id) m;
  -- Keep exact paise totals even with percentages such as 33.33 / 33.33 / 33.34.
  insert into public.contributions(round_id, member_id, amount_paise)
  select r.id, shares.user_id, shares.amount + case when shares.owner_number = 1 then c.monthly_amount_paise - shares.allocated else 0 end
  from public.rounds r cross join (
    select user_id, floor(c.monthly_amount_paise * contribution_share_bps / 10000.0)::bigint as amount,
      sum(floor(c.monthly_amount_paise * contribution_share_bps / 10000.0)::bigint) over (partition by payout_position) as allocated,
      row_number() over (partition by payout_position order by is_admin desc, joined_at, user_id) as owner_number
    from public.chitti_members where chitti_id = c.id
  ) shares where r.chitti_id = c.id and r.round_number > c.imported_completed_months;
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

-- Keep the tested non-shared conversion path; shared positions need group-aware ranking.
alter function public.convert_pending_chitti_to_existing(uuid, smallint, jsonb) rename to convert_pending_chitti_without_shares;
revoke all on function public.convert_pending_chitti_without_shares(uuid, smallint, jsonb) from public, anon, authenticated;

create function public.convert_pending_chitti_to_existing(p_chitti_id uuid, p_completed_months smallint, p_order jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  c public.chittis;
  positions int[];
  seen int[] := '{}';
  item jsonb;
  old_position int;
  idx int := 1;
  mapping jsonb := '[]';
  invitations_before jsonb;
begin
  select * into c from public.chittis where id = p_chitti_id for update;
  if c.id is null or not public.is_chitti_admin(c.id) then raise exception 'Administrator access required'; end if;
  if not exists(select 1 from public.invitations where chitti_id = c.id and status in ('pending', 'accepted') and coowner_share_bps is not null) then
    perform public.convert_pending_chitti_without_shares(c.id, p_completed_months, p_order); return;
  end if;
  if not c.is_imported or c.status <> 'inviting' or c.locked_at is not null or exists(select 1 from public.rounds where chitti_id = c.id) then
    raise exception 'Only a pending existing chitti can have its shared ranking edited';
  end if;
  if p_completed_months is distinct from c.imported_completed_months then raise exception 'Editing the ranking cannot change the imported completed months'; end if;
  select array_agg(position order by position) into positions from (
    select payout_position::int position from public.chitti_members where chitti_id = c.id and payout_position <> 1
    union select payout_position::int from public.invitations where chitti_id = c.id and status = 'pending' and payout_position <> 1
  ) slots;
  if p_order is null or jsonb_typeof(p_order) <> 'array' or jsonb_array_length(p_order) <> coalesce(cardinality(positions), 0) then
    raise exception 'Arrange each payout position exactly once; co-owners move together';
  end if;
  for item in select value from jsonb_array_elements(p_order) loop
    old_position := null;
    if item->>'kind' = 'member' then
      select payout_position into old_position from public.chitti_members where chitti_id = c.id and user_id = (item->>'id')::uuid;
    elsif item->>'kind' = 'invitation' then
      select payout_position into old_position from public.invitations where chitti_id = c.id and id = (item->>'id')::uuid and status = 'pending';
    end if;
    if old_position is null or old_position < 2 or old_position > c.member_count or old_position = any(seen) then
      raise exception 'A payout position is missing, repeated or unavailable';
    end if;
    seen := array_append(seen, old_position);
    mapping := mapping || jsonb_build_array(jsonb_build_object('old_position', old_position, 'new_position', positions[idx]));
    idx := idx + 1;
  end loop;
  select jsonb_agg(jsonb_build_object('id', id, 'position', payout_position)) into invitations_before
  from public.invitations where chitti_id = c.id and status in ('pending', 'accepted');
  update public.invitations set payout_position = null where chitti_id = c.id and status in ('pending', 'accepted');
  update public.chitti_members m set payout_position = map.new_position
  from jsonb_to_recordset(mapping) map(old_position int, new_position int)
  where m.chitti_id = c.id and m.payout_position = map.old_position;
  update public.invitations i set payout_position = coalesce(map.new_position, previous.position)
  from jsonb_to_recordset(invitations_before) previous(id uuid, position int)
  left join jsonb_to_recordset(mapping) map(old_position int, new_position int) on map.old_position = previous.position
  where i.id = previous.id;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (auth.uid(), c.id, 'chitti.ranking_updated', 'chitti', c.id::text, jsonb_build_object('position_mapping', mapping, 'manual_order', p_order));
  perform public.notify_chitti_members(c.id, 'chitti.ranking_updated', 'Payout ranking saved',
    'The administrator updated the payout ranking. Co-owners remain together in the same month.', '/chitti/' || c.id, gen_random_uuid()::text, auth.uid());
  perform public.activate_imported_chitti(c.id);
end;
$$;

alter function public.get_app_snapshot() rename to get_app_snapshot_before_pending_shares;
revoke all on function public.get_app_snapshot_before_pending_shares() from public, anon, authenticated;
create function public.get_app_snapshot() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare snapshot jsonb;
begin
  snapshot := public.get_app_snapshot_before_pending_shares();
  snapshot := jsonb_set(snapshot, '{pendingInvitations}', coalesce((select jsonb_agg(i || jsonb_build_object(
    'coOwnerShareBps', invitation.coowner_share_bps,
    'contributionAmountPaise', floor((i->>'monthlyAmountPaise')::bigint * coalesce(invitation.coowner_share_bps, 10000) / 10000.0)))
    from jsonb_array_elements(snapshot->'pendingInvitations') i join public.invitations invitation on invitation.id = (i->>'id')::uuid), '[]'::jsonb));
  return jsonb_set(snapshot, '{chittis}', coalesce((select jsonb_agg(c || jsonb_build_object('invitations',
    coalesce((select jsonb_agg(i || jsonb_build_object('coOwnerSourceInvitationId', invitation.coowner_source_invitation_id,
      'coOwnerSourceMemberId', coalesce(invitation.coowner_source_member_id, parent.accepted_by)))
      from jsonb_array_elements(c->'invitations') i join public.invitations invitation on invitation.id = (i->>'id')::uuid
      left join public.invitations parent on parent.id = invitation.coowner_source_invitation_id), '[]'::jsonb)))
    from jsonb_array_elements(snapshot->'chittis') c), '[]'::jsonb));
end;
$$;

revoke all on function public.add_coowner_invitation(uuid, uuid, smallint, text, text, text, uuid) from public, anon;
grant execute on function public.add_coowner_invitation(uuid, uuid, smallint, text, text, text, uuid) to authenticated;
revoke all on function public.redeem_invitation(text, uuid) from public, anon;
grant execute on function public.redeem_invitation(text, uuid) to authenticated;
revoke all on function public.convert_pending_chitti_to_existing(uuid, smallint, jsonb) from public, anon;
grant execute on function public.convert_pending_chitti_to_existing(uuid, smallint, jsonb) to authenticated;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

commit;
