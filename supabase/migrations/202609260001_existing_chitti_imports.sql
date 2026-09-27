begin;

alter table public.chittis
  add column is_imported boolean not null default false,
  add column imported_completed_months smallint not null default 0,
  add constraint chittis_imported_completed_months_check
    check (imported_completed_months between 0 and member_count);

alter table public.invitations
  add column payout_position smallint,
  add constraint invitations_payout_position_check
    check (payout_position is null or payout_position between 2 and 50);

create unique index invitations_chitti_payout_position_idx
  on public.invitations(chitti_id, payout_position)
  where payout_position is not null;

create function public.activate_imported_chitti(p_chitti_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_joined int;
begin
  select * into v_chitti
  from public.chittis
  where id = p_chitti_id
  for update;

  if v_chitti.id is null or not v_chitti.is_imported then
    raise exception 'Imported chitti not found';
  end if;
  if v_chitti.status not in ('inviting', 'ready') then
    return;
  end if;

  select count(*) into v_joined
  from public.chitti_members
  where chitti_id = p_chitti_id
    and payout_position is not null;

  if v_joined <> v_chitti.member_count then
    return;
  end if;
  if exists(
    select 1
    from generate_series(1, v_chitti.member_count) expected(position)
    where not exists(
      select 1 from public.chitti_members member
      where member.chitti_id = p_chitti_id
        and member.payout_position = expected.position
    )
  ) then
    raise exception 'Every imported payout month must be assigned exactly once';
  end if;

  insert into public.rounds(chitti_id, round_number, due_date, recipient_id, status)
  select
    v_chitti.id,
    member.payout_position,
    (v_chitti.first_due_date + make_interval(months => member.payout_position - 1))::date,
    member.user_id,
    case
      when member.payout_position <= v_chitti.imported_completed_months
        then 'completed'::public.round_status
      when member.payout_position = v_chitti.imported_completed_months + 1
        then 'collecting'::public.round_status
      else 'upcoming'::public.round_status
    end
  from public.chitti_members member
  where member.chitti_id = v_chitti.id
  order by member.payout_position;

  insert into public.contributions(round_id, member_id)
  select round_item.id, member.user_id
  from public.rounds round_item
  cross join public.chitti_members member
  where round_item.chitti_id = v_chitti.id
    and member.chitti_id = v_chitti.id
    and round_item.round_number > v_chitti.imported_completed_months;

  insert into public.payouts(round_id, status)
  select round_item.id,
    case
      when round_item.round_number <= v_chitti.imported_completed_months
        then 'paid'::public.payout_status
      else 'blocked'::public.payout_status
    end
  from public.rounds round_item
  where round_item.chitti_id = v_chitti.id;

  update public.chittis
  set status = case
      when imported_completed_months = member_count then 'completed'::public.chitti_status
      else 'active'::public.chitti_status
    end,
    locked_at = now()
  where id = v_chitti.id;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(), v_chitti.id, 'chitti.import_activated', 'chitti', v_chitti.id::text,
    jsonb_build_object('completed_months', v_chitti.imported_completed_months)
  );

  perform public.notify_chitti_members(
    v_chitti.id,
    'chitti.import_activated',
    'Existing chitti is ready',
    'Everyone joined. The saved payout order and current month are now active.',
    '/chitti/' || v_chitti.id,
    v_chitti.id::text,
    null
  );
end;
$$;

create function public.apply_imported_invitation_position()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
begin
  select * into v_chitti
  from public.chittis
  where id = new.chitti_id;

  if v_chitti.is_imported
     and new.payout_position is not null
     and new.status = 'accepted'
     and old.status <> 'accepted' then
    update public.chitti_members
    set payout_position = new.payout_position
    where chitti_id = new.chitti_id
      and user_id = new.accepted_by;
  end if;
  return new;
end;
$$;

create trigger invitations_apply_imported_position
after update of status on public.invitations
for each row execute function public.apply_imported_invitation_position();

create function public.activate_imported_after_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_imported boolean;
begin
  if new.status = 'accepted' and old.status <> 'accepted' then
    select chitti.is_imported into v_is_imported
    from public.chittis chitti
    where chitti.id = new.chitti_id;
    if v_is_imported then
      perform public.activate_imported_chitti(new.chitti_id);
    end if;
  end if;
  return new;
end;
$$;

create constraint trigger invitations_activate_imported_chitti
after update on public.invitations
deferrable initially deferred
for each row execute function public.activate_imported_after_invitation();

create function public.guard_imported_invitation_position()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_chitti public.chittis;
begin
  select * into v_chitti from public.chittis where id = new.chitti_id;
  if v_chitti.is_imported
     and v_chitti.status = 'inviting'
     and not new.late_join
     and new.payout_position is null then
    raise exception 'Imported chitti invitations require a payout month';
  end if;
  return new;
end;
$$;

create trigger invitations_guard_imported_position
before insert on public.invitations
for each row execute function public.guard_imported_invitation_position();

create function public.import_existing_chitti(input jsonb)
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
  v_completed int;
  v_expected_position int := 2;
begin
  if not public.is_admin() then
    raise exception 'Only the administrator can import a chitti';
  end if;

  v_count := (input->>'memberCount')::int;
  v_completed := (input->>'completedMonths')::int;
  if v_count not between 2 and 50 then
    raise exception 'Member count must be between 2 and 50';
  end if;
  if v_completed not between 0 and v_count then
    raise exception 'Completed months must be between zero and the member count';
  end if;
  if jsonb_array_length(input->'invites') <> v_count - 1 then
    raise exception 'Invitation count must equal member count minus one';
  end if;
  if (input->>'firstDueDate')::date < (input->>'startDate')::date then
    raise exception 'The first due date cannot be before the start date';
  end if;

  insert into public.chittis(
    name, description, admin_id, monthly_amount_paise, member_count,
    start_date, first_due_date, due_day, upi_id, payee_name, status,
    is_imported, imported_completed_months
  ) values (
    input->>'name', nullif(input->>'description', ''), auth.uid(),
    (input->>'monthlyAmountPaise')::bigint, v_count,
    (input->>'startDate')::date, (input->>'firstDueDate')::date,
    (input->>'dueDay')::smallint, input->>'upiId', input->>'payeeName',
    'inviting', true, v_completed
  ) returning * into v_chitti;

  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position)
  values (v_chitti.id, auth.uid(), true, 1);

  for v_invite in
    select value from jsonb_array_elements(input->'invites')
  loop
    if coalesce((v_invite->>'payoutPosition')::int, 0) <> v_expected_position then
      raise exception 'Imported members must be listed once in payout-month order';
    end if;
    if lower(v_invite->>'email') = lower(coalesce(auth.jwt()->>'email', '')) then
      raise exception 'The administrator cannot also be invited as a member';
    end if;

    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.invitations(
      chitti_id, invited_name, invited_email, invited_phone, token_hash, payout_position
    ) values (
      v_chitti.id, btrim(v_invite->>'name'), lower(btrim(v_invite->>'email')),
      btrim(v_invite->>'phone'), extensions.digest(v_token, 'sha256'), v_expected_position
    ) returning id into v_invitation_id;

    v_links := v_links || jsonb_build_array(jsonb_build_object(
      'id', v_invitation_id,
      'name', v_invite->>'name',
      'email', lower(v_invite->>'email'),
      'payoutPosition', v_expected_position,
      'token', v_token
    ));

    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    select id, 'invitation.created', 'You have an existing Chitti invitation',
      'Open Chitti to join the saved payout order.',
      '/invite?invitation=' || v_invitation_id, 'invite:' || v_invitation_id
    from public.profiles
    where lower(email) = lower(v_invite->>'email')
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;

    v_expected_position := v_expected_position + 1;
  end loop;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(), v_chitti.id, 'chitti.imported', 'chitti', v_chitti.id::text,
    jsonb_build_object('completed_months', v_completed, 'member_count', v_count)
  );

  return jsonb_build_object('chitti_id', v_chitti.id, 'invitations', v_links);
end;
$$;

alter function public.get_app_snapshot() rename to get_app_snapshot_without_existing_chitti_imports;

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
  v_snapshot := public.get_app_snapshot_without_existing_chitti_imports();
  return jsonb_set(
    v_snapshot,
    '{chittis}',
    coalesce((
      select jsonb_agg(
        chitti_item || jsonb_build_object(
          'isImported', chitti.is_imported,
          'importedCompletedMonths', chitti.imported_completed_months
        ) order by chitti_order
      )
      from jsonb_array_elements(v_snapshot->'chittis') with ordinality
        as chitti_items(chitti_item, chitti_order)
      join public.chittis chitti on chitti.id = (chitti_item->>'id')::uuid
    ), '[]'::jsonb),
    true
  );
end;
$$;

revoke all on function public.activate_imported_chitti(uuid) from public, anon, authenticated;
revoke all on function public.apply_imported_invitation_position() from public, anon, authenticated;
revoke all on function public.activate_imported_after_invitation() from public, anon, authenticated;
revoke all on function public.guard_imported_invitation_position() from public, anon, authenticated;
revoke all on function public.import_existing_chitti(jsonb) from public, anon;
grant execute on function public.import_existing_chitti(jsonb) to authenticated;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

commit;
