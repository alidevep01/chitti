begin;

create extension if not exists pgcrypto with schema extensions;

create type public.app_role as enum ('admin', 'member');
create type public.chitti_status as enum ('draft', 'inviting', 'ready', 'shuffle_scheduled', 'awaiting_approval', 'active', 'completed', 'cancelled');
create type public.invitation_status as enum ('pending', 'accepted', 'revoked', 'expired');
create type public.approval_status as enum ('pending', 'accepted', 'rejected');
create type public.shuffle_status as enum ('pending', 'revealed', 'rejected', 'locked');
create type public.round_status as enum ('upcoming', 'collecting', 'ready_for_payout', 'completed');
create type public.contribution_status as enum ('due', 'submitted', 'confirmed', 'rejected', 'overdue');
create type public.payment_method as enum ('upi', 'cash');
create type public.payout_status as enum ('blocked', 'ready', 'paid');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null check (char_length(display_name) between 2 and 80),
  email text not null,
  phone text not null default '',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index profiles_email_lower_idx on public.profiles (lower(email));

create table public.app_roles (
  user_id uuid primary key references public.profiles(id) on delete restrict,
  role public.app_role not null default 'member',
  created_at timestamptz not null default now()
);

create table public.chittis (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 100),
  description text check (char_length(description) <= 500),
  admin_id uuid not null references public.profiles(id) on delete restrict,
  monthly_amount_paise bigint not null check (monthly_amount_paise >= 10000),
  member_count smallint not null check (member_count between 2 and 24),
  first_due_date date not null,
  due_day smallint not null check (due_day between 1 and 31),
  upi_id text not null check (char_length(upi_id) between 3 and 120),
  payee_name text not null check (char_length(payee_name) between 2 and 100),
  status public.chitti_status not null default 'draft',
  shuffle_scheduled_at timestamptz,
  locked_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index chittis_admin_status_idx on public.chittis(admin_id, status);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  chitti_id uuid not null references public.chittis(id) on delete restrict,
  invited_name text not null,
  invited_email text not null,
  invited_phone text not null,
  token_hash bytea not null unique,
  status public.invitation_status not null default 'pending',
  accepted_by uuid references public.profiles(id) on delete restrict,
  accepted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '30 days'),
  created_at timestamptz not null default now(),
  unique (chitti_id, invited_email)
);
create index invitations_chitti_status_idx on public.invitations(chitti_id, status);

create table public.chitti_members (
  chitti_id uuid not null references public.chittis(id) on delete restrict,
  user_id uuid not null references public.profiles(id) on delete restrict,
  is_admin boolean not null default false,
  payout_position smallint,
  joined_at timestamptz not null default now(),
  primary key (chitti_id, user_id),
  unique (chitti_id, payout_position)
);

create table public.shuffle_runs (
  id uuid primary key default gen_random_uuid(),
  chitti_id uuid not null references public.chittis(id) on delete restrict,
  run_number smallint not null,
  idempotency_key uuid not null,
  status public.shuffle_status not null default 'pending',
  result_hash text,
  started_by uuid not null references public.profiles(id) on delete restrict,
  started_at timestamptz not null default now(),
  locked_at timestamptz,
  unique (chitti_id, run_number),
  unique (chitti_id, idempotency_key)
);

create table public.shuffle_assignments (
  shuffle_run_id uuid not null references public.shuffle_runs(id) on delete restrict,
  member_id uuid not null references public.profiles(id) on delete restrict,
  payout_position smallint not null,
  primary key (shuffle_run_id, member_id),
  unique (shuffle_run_id, payout_position)
);

create table public.shuffle_approvals (
  shuffle_run_id uuid not null references public.shuffle_runs(id) on delete restrict,
  member_id uuid not null references public.profiles(id) on delete restrict,
  status public.approval_status not null default 'pending',
  reason text check (char_length(reason) <= 500),
  responded_at timestamptz,
  primary key (shuffle_run_id, member_id)
);

create table public.rounds (
  id uuid primary key default gen_random_uuid(),
  chitti_id uuid not null references public.chittis(id) on delete restrict,
  round_number smallint not null,
  due_date date not null,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  status public.round_status not null default 'upcoming',
  created_at timestamptz not null default now(),
  unique (chitti_id, round_number),
  unique (chitti_id, recipient_id)
);
create index rounds_chitti_status_due_idx on public.rounds(chitti_id, status, due_date);

create table public.contributions (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.rounds(id) on delete restrict,
  member_id uuid not null references public.profiles(id) on delete restrict,
  status public.contribution_status not null default 'due',
  method public.payment_method,
  reference text check (char_length(reference) <= 100),
  submitted_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete restrict,
  confirmed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (round_id, member_id)
);
create index contributions_round_status_idx on public.contributions(round_id, status);

create table public.payouts (
  round_id uuid primary key references public.rounds(id) on delete restrict,
  status public.payout_status not null default 'blocked',
  reference text check (char_length(reference) <= 100),
  confirmed_by uuid references public.profiles(id) on delete restrict,
  paid_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  kind text not null,
  title text not null,
  message text not null,
  route text,
  dedupe_key text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index notifications_user_dedupe_idx on public.notifications(user_id, dedupe_key) where dedupe_key is not null;
create index notifications_user_created_idx on public.notifications(user_id, created_at desc);

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, endpoint)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete restrict,
  chitti_id uuid references public.chittis(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id text,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_events_chitti_created_idx on public.audit_events(chitti_id, created_at desc);

create function public.touch_updated_at() returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
create trigger chittis_touch before update on public.chittis for each row execute function public.touch_updated_at();
create trigger contributions_touch before update on public.contributions for each row execute function public.touch_updated_at();
create trigger payouts_touch before update on public.payouts for each row execute function public.touch_updated_at();

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name, email, avatar_url)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(new.email, '@', 1)), new.email, new.raw_user_meta_data->>'avatar_url')
  on conflict (id) do nothing;
  insert into public.app_roles(user_id, role) values (new.id, 'member') on conflict (user_id) do nothing;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.app_roles where user_id = auth.uid() and role = 'admin');
$$;
create function public.is_chitti_member(p_chitti_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.chitti_members where chitti_id = p_chitti_id and user_id = auth.uid());
$$;
create function public.is_chitti_admin(p_chitti_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.chittis where id = p_chitti_id and admin_id = auth.uid()) and public.is_admin();
$$;

create function public.notify_chitti_members(p_chitti_id uuid, p_kind text, p_title text, p_message text, p_route text, p_dedupe_suffix text default null, p_exclude uuid default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select cm.user_id, p_kind, p_title, p_message, p_route,
    case when p_dedupe_suffix is null then null else p_kind || ':' || p_chitti_id || ':' || p_dedupe_suffix end
  from public.chitti_members cm
  where cm.chitti_id = p_chitti_id and (p_exclude is null or cm.user_id <> p_exclude)
  on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
$$;
revoke all on function public.notify_chitti_members(uuid, text, text, text, text, text, uuid) from public, anon, authenticated;

create function public.bootstrap_admin(p_email text) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  select id into v_id from public.profiles where lower(email) = lower(p_email);
  if v_id is null then raise exception 'The user must sign in once before bootstrap'; end if;
  update public.app_roles set role = 'admin' where user_id = v_id;
  return v_id;
end; $$;
revoke all on function public.bootstrap_admin(text) from public, anon, authenticated;

alter table public.profiles enable row level security;
alter table public.app_roles enable row level security;
alter table public.chittis enable row level security;
alter table public.invitations enable row level security;
alter table public.chitti_members enable row level security;
alter table public.shuffle_runs enable row level security;
alter table public.shuffle_assignments enable row level security;
alter table public.shuffle_approvals enable row level security;
alter table public.rounds enable row level security;
alter table public.contributions enable row level security;
alter table public.payouts enable row level security;
alter table public.notifications enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.audit_events enable row level security;

create policy profiles_self_select on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy profiles_self_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy roles_self_select on public.app_roles for select to authenticated using (user_id = auth.uid());
create policy chittis_member_select on public.chittis for select to authenticated using (public.is_chitti_member(id));
create policy invitations_admin_select on public.invitations for select to authenticated using (public.is_chitti_admin(chitti_id));
create policy members_group_select on public.chitti_members for select to authenticated using (public.is_chitti_member(chitti_id));
create policy shuffle_runs_member_select on public.shuffle_runs for select to authenticated using (public.is_chitti_member(chitti_id));
create policy shuffle_assignments_member_select on public.shuffle_assignments for select to authenticated using (exists(select 1 from public.shuffle_runs sr where sr.id = shuffle_run_id and public.is_chitti_member(sr.chitti_id)));
create policy shuffle_approvals_member_select on public.shuffle_approvals for select to authenticated using (exists(select 1 from public.shuffle_runs sr where sr.id = shuffle_run_id and public.is_chitti_member(sr.chitti_id)));
create policy rounds_member_select on public.rounds for select to authenticated using (public.is_chitti_member(chitti_id));
create policy contributions_own_or_admin_select on public.contributions for select to authenticated using (member_id = auth.uid() or exists(select 1 from public.rounds r where r.id = round_id and public.is_chitti_admin(r.chitti_id)));
create policy payouts_member_select on public.payouts for select to authenticated using (exists(select 1 from public.rounds r where r.id = round_id and public.is_chitti_member(r.chitti_id)));
create policy notifications_self_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy push_self_all on public.push_subscriptions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy audit_admin_select on public.audit_events for select to authenticated using (chitti_id is not null and public.is_chitti_admin(chitti_id));

create function public.create_chitti(input jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_chitti public.chittis; v_invite jsonb; v_token text; v_invitation_id uuid; v_links jsonb := '[]'::jsonb; v_count int;
begin
  if not public.is_admin() then raise exception 'Only the administrator can create a chitti'; end if;
  v_count := (input->>'memberCount')::int;
  if jsonb_array_length(input->'invites') <> v_count - 1 then raise exception 'Invitation count must equal member count minus one'; end if;
  insert into public.chittis(name, description, admin_id, monthly_amount_paise, member_count, first_due_date, due_day, upi_id, payee_name, status)
  values (input->>'name', nullif(input->>'description',''), auth.uid(), (input->>'monthlyAmountPaise')::bigint, v_count,
    (input->>'firstDueDate')::date, (input->>'dueDay')::smallint, input->>'upiId', input->>'payeeName', 'inviting') returning * into v_chitti;
  insert into public.chitti_members(chitti_id, user_id, is_admin, payout_position) values (v_chitti.id, auth.uid(), true, 1);
  for v_invite in select value from jsonb_array_elements(input->'invites') loop
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.invitations(chitti_id, invited_name, invited_email, invited_phone, token_hash)
    values (v_chitti.id, v_invite->>'name', lower(v_invite->>'email'), v_invite->>'phone', extensions.digest(v_token, 'sha256')) returning id into v_invitation_id;
    v_links := v_links || jsonb_build_array(jsonb_build_object('id', v_invitation_id, 'name', v_invite->>'name', 'email', lower(v_invite->>'email'), 'token', v_token));
    insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
      select id, 'invitation.created', 'You have a private Chitti invitation', 'Open Chitti to review your invitation.', '/invite?invitation=' || v_invitation_id, 'invite:' || v_chitti.id
      from public.profiles where lower(email) = lower(v_invite->>'email')
      on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
  end loop;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id) values (auth.uid(), v_chitti.id, 'chitti.created', 'chitti', v_chitti.id::text);
  return jsonb_build_object('chitti_id', v_chitti.id, 'invitations', v_links);
end; $$;

create function public.redeem_invitation(p_token text default null, p_invitation_id uuid default null) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_invite public.invitations; v_email text; v_joined int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_email := lower(coalesce(auth.jwt()->>'email', ''));
  select * into v_invite from public.invitations where
    (p_token is not null and token_hash = extensions.digest(p_token, 'sha256')) or (p_invitation_id is not null and id = p_invitation_id)
    for update;
  if v_invite.id is null or v_invite.status <> 'pending' or v_invite.expires_at < now() then raise exception 'Invitation is invalid or expired'; end if;
  if lower(v_invite.invited_email) <> v_email then raise exception 'Sign in with the invited Google email'; end if;
  update public.profiles set phone = case when btrim(phone) = '' then v_invite.invited_phone else phone end where id = auth.uid();
  insert into public.chitti_members(chitti_id, user_id) values (v_invite.chitti_id, auth.uid());
  update public.invitations set status = 'accepted', accepted_by = auth.uid(), accepted_at = now() where id = v_invite.id;
  select count(*) into v_joined from public.chitti_members where chitti_id = v_invite.chitti_id;
  update public.chittis set status = case when v_joined = member_count then 'ready' else 'inviting' end where id = v_invite.chitti_id;
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    select admin_id, 'invitation.accepted', v_invite.invited_name || ' joined', 'A member accepted the invitation.', '/chitti/' || v_invite.chitti_id, 'joined:' || v_invite.id from public.chittis where id = v_invite.chitti_id;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id) values (auth.uid(), v_invite.chitti_id, 'invitation.accepted', 'invitation', v_invite.id::text);
  return v_invite.chitti_id;
end; $$;

create function public.regenerate_invitation(p_invitation_id uuid) returns text language plpgsql security definer set search_path = '' as $$
declare v_invite public.invitations; v_token text;
begin
  select * into v_invite from public.invitations where id = p_invitation_id for update;
  if v_invite.id is null or v_invite.status <> 'pending' or not public.is_chitti_admin(v_invite.chitti_id) then raise exception 'Pending invitation not found'; end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  update public.invitations set token_hash = extensions.digest(v_token, 'sha256'), expires_at = now() + interval '30 days' where id = p_invitation_id;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id) values (auth.uid(), v_invite.chitti_id, 'invitation.regenerated', 'invitation', p_invitation_id::text);
  return v_token;
end; $$;

create function public.schedule_shuffle(p_chitti_id uuid, p_starts_at timestamptz) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_chitti_admin(p_chitti_id) then raise exception 'Administrator access required'; end if;
  update public.chittis set status = 'shuffle_scheduled', shuffle_scheduled_at = p_starts_at where id = p_chitti_id and status = 'ready';
  if not found then raise exception 'Chitti is not ready for shuffle'; end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail) values (auth.uid(), p_chitti_id, 'shuffle.scheduled', 'chitti', p_chitti_id::text, jsonb_build_object('starts_at', p_starts_at));
  perform public.notify_chitti_members(p_chitti_id, 'shuffle.scheduled', 'Payout shuffle scheduled', 'Open Chitti to join the live payout-order reveal.', '/chitti/' || p_chitti_id || '/shuffle', p_starts_at::text, null);
end; $$;

create function public.run_shuffle(p_chitti_id uuid, p_idempotency_key uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_run_id uuid; v_run_number int; v_hash text;
begin
  if not public.is_chitti_admin(p_chitti_id) then raise exception 'Administrator access required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_chitti_id::text, 0));
  select id into v_run_id from public.shuffle_runs where chitti_id = p_chitti_id and idempotency_key = p_idempotency_key;
  if v_run_id is not null then return v_run_id; end if;
  if not exists(select 1 from public.chittis where id = p_chitti_id and status = 'shuffle_scheduled') then raise exception 'Shuffle is not scheduled'; end if;
  select coalesce(max(run_number), 0) + 1 into v_run_number from public.shuffle_runs where chitti_id = p_chitti_id;
  insert into public.shuffle_runs(chitti_id, run_number, idempotency_key, status, started_by) values (p_chitti_id, v_run_number, p_idempotency_key, 'pending', auth.uid()) returning id into v_run_id;
  insert into public.shuffle_assignments(shuffle_run_id, member_id, payout_position)
    select v_run_id, user_id, (row_number() over (order by is_admin desc, case when is_admin then '' else encode(extensions.gen_random_bytes(16), 'hex') end))::smallint
    from public.chitti_members where chitti_id = p_chitti_id;
  select encode(extensions.digest(string_agg(member_id::text, ',' order by payout_position), 'sha256'), 'hex') into v_hash from public.shuffle_assignments where shuffle_run_id = v_run_id;
  update public.shuffle_runs set status = 'revealed', result_hash = v_hash where id = v_run_id;
  insert into public.shuffle_approvals(shuffle_run_id, member_id) select v_run_id, user_id from public.chitti_members where chitti_id = p_chitti_id;
  update public.chittis set status = 'awaiting_approval' where id = p_chitti_id;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail) values (auth.uid(), p_chitti_id, 'shuffle.revealed', 'shuffle_run', v_run_id::text, jsonb_build_object('result_hash', v_hash));
  perform public.notify_chitti_members(p_chitti_id, 'shuffle.revealed', 'Your payout order is ready', 'Review the result and record your decision.', '/chitti/' || p_chitti_id || '/shuffle', v_run_id::text, null);
  return v_run_id;
end; $$;

create function public.respond_to_shuffle(p_chitti_id uuid, p_accepted boolean, p_reason text default null) returns void language plpgsql security definer set search_path = '' as $$
declare v_run public.shuffle_runs; v_pending int; v_assignment record; v_round_id uuid;
begin
  if not public.is_chitti_member(p_chitti_id) then raise exception 'Membership required'; end if;
  select * into v_run from public.shuffle_runs where chitti_id = p_chitti_id and status = 'revealed' order by run_number desc limit 1 for update;
  if v_run.id is null then raise exception 'No active shuffle approval'; end if;
  update public.shuffle_approvals set status = case when p_accepted then 'accepted' else 'rejected' end, reason = p_reason, responded_at = now()
    where shuffle_run_id = v_run.id and member_id = auth.uid() and status = 'pending';
  if not found then raise exception 'Approval already recorded'; end if;
  if not p_accepted then
    update public.shuffle_runs set status = 'rejected' where id = v_run.id;
    update public.chittis set status = 'ready' where id = p_chitti_id;
    insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail) values (auth.uid(), p_chitti_id, 'shuffle.rejected', 'shuffle_run', v_run.id::text, jsonb_build_object('reason', p_reason));
    perform public.notify_chitti_members(p_chitti_id, 'shuffle.rejected', 'Payout order was not accepted', 'The administrator will discuss the result before scheduling another shuffle.', '/chitti/' || p_chitti_id, v_run.id::text, null);
    return;
  end if;
  select count(*) into v_pending from public.shuffle_approvals where shuffle_run_id = v_run.id and status <> 'accepted';
  if v_pending = 0 then
    update public.chitti_members m set payout_position = a.payout_position from public.shuffle_assignments a where a.shuffle_run_id = v_run.id and m.chitti_id = p_chitti_id and m.user_id = a.member_id;
    update public.shuffle_runs set status = 'locked', locked_at = now() where id = v_run.id;
    update public.chittis set status = 'active', locked_at = now() where id = p_chitti_id;
    for v_assignment in select * from public.shuffle_assignments where shuffle_run_id = v_run.id order by payout_position loop
      insert into public.rounds(chitti_id, round_number, due_date, recipient_id, status)
      select p_chitti_id, v_assignment.payout_position,
        (first_due_date + make_interval(months => v_assignment.payout_position - 1))::date,
        v_assignment.member_id, case when v_assignment.payout_position = 1 and first_due_date <= (now() at time zone 'Asia/Kolkata')::date then 'collecting'::public.round_status else 'upcoming'::public.round_status end
      from public.chittis where id = p_chitti_id returning id into v_round_id;
      insert into public.contributions(round_id, member_id) select v_round_id, user_id from public.chitti_members where chitti_id = p_chitti_id;
      insert into public.payouts(round_id) values (v_round_id);
    end loop;
    insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id) values (auth.uid(), p_chitti_id, 'shuffle.locked', 'shuffle_run', v_run.id::text);
    perform public.notify_chitti_members(p_chitti_id, 'chitti.activated', 'Payout order locked', 'Everyone agreed. Monthly contribution tracking is now active.', '/chitti/' || p_chitti_id, v_run.id::text, null);
  end if;
end; $$;

create function public.submit_contribution(p_round_id uuid, p_method public.payment_method, p_reference text default null) returns void language plpgsql security definer set search_path = '' as $$
declare v_chitti_id uuid;
begin
  select chitti_id into v_chitti_id from public.rounds where id = p_round_id and status = 'collecting';
  if v_chitti_id is null or not public.is_chitti_member(v_chitti_id) then raise exception 'This round is not open'; end if;
  update public.contributions set status = 'submitted', method = p_method, reference = nullif(p_reference,''), submitted_at = now(), confirmed_at = null, reviewed_by = null
    where round_id = p_round_id and member_id = auth.uid() and status in ('due', 'rejected', 'overdue');
  if not found then raise exception 'Contribution cannot be submitted'; end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id) values (auth.uid(), v_chitti_id, 'contribution.submitted', 'round', p_round_id::text);
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    select admin_id, 'contribution.submitted', 'Payment awaiting review', 'A member marked a contribution as paid.', '/chitti/' || v_chitti_id, 'submitted:' || p_round_id || ':' || auth.uid()
    from public.chittis where id = v_chitti_id on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end; $$;

create function public.review_contribution(p_contribution_id uuid, p_accepted boolean) returns void language plpgsql security definer set search_path = '' as $$
declare v_round_id uuid; v_chitti_id uuid; v_remaining int;
begin
  select c.round_id, r.chitti_id into v_round_id, v_chitti_id from public.contributions c join public.rounds r on r.id = c.round_id where c.id = p_contribution_id;
  if not public.is_chitti_admin(v_chitti_id) then raise exception 'Administrator access required'; end if;
  update public.contributions set status = case when p_accepted then 'confirmed' else 'rejected' end, reviewed_by = auth.uid(), confirmed_at = case when p_accepted then now() else null end where id = p_contribution_id and status = 'submitted';
  if not found then raise exception 'Contribution is not awaiting review'; end if;
  if p_accepted then
    select count(*) into v_remaining from public.contributions where round_id = v_round_id and status <> 'confirmed';
    if v_remaining = 0 then update public.rounds set status = 'ready_for_payout' where id = v_round_id; update public.payouts set status = 'ready' where round_id = v_round_id; end if;
  end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail) values (auth.uid(), v_chitti_id, 'contribution.reviewed', 'contribution', p_contribution_id::text, jsonb_build_object('accepted', p_accepted));
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    select member_id, 'contribution.reviewed', case when p_accepted then 'Payment confirmed' else 'Payment needs attention' end,
      case when p_accepted then 'The administrator confirmed your contribution.' else 'The administrator could not confirm your contribution. Please review it.' end,
      '/chitti/' || v_chitti_id, 'reviewed:' || p_contribution_id || ':' || p_accepted from public.contributions where id = p_contribution_id
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end; $$;

create function public.confirm_payout(p_round_id uuid, p_reference text default null) returns void language plpgsql security definer set search_path = '' as $$
declare v_round public.rounds; v_remaining int;
begin
  select * into v_round from public.rounds where id = p_round_id for update;
  if not public.is_chitti_admin(v_round.chitti_id) then raise exception 'Administrator access required'; end if;
  update public.payouts set status = 'paid', reference = nullif(p_reference,''), confirmed_by = auth.uid(), paid_at = now() where round_id = p_round_id and status = 'ready';
  if not found then raise exception 'Payout is not ready'; end if;
  update public.rounds set status = 'completed' where id = p_round_id;
  update public.rounds set status = 'collecting' where chitti_id = v_round.chitti_id and round_number = v_round.round_number + 1 and due_date <= (now() at time zone 'Asia/Kolkata')::date and status = 'upcoming';
  select count(*) into v_remaining from public.rounds where chitti_id = v_round.chitti_id and status <> 'completed';
  if v_remaining = 0 then update public.chittis set status = 'completed' where id = v_round.chitti_id; end if;
  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id) values (auth.uid(), v_round.chitti_id, 'payout.confirmed', 'round', p_round_id::text);
  perform public.notify_chitti_members(v_round.chitti_id, 'payout.confirmed', 'Monthly payout delivered', 'The administrator recorded this month''s payout as delivered.', '/chitti/' || v_round.chitti_id, p_round_id::text, null);
end; $$;

create function public.mark_notification_read(p_notification_id uuid) returns void language sql security definer set search_path = '' as $$
  update public.notifications set read_at = coalesce(read_at, now()) where id = p_notification_id and user_id = auth.uid();
$$;

create function public.register_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default null) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  insert into public.push_subscriptions(user_id, endpoint, p256dh, auth, user_agent) values (auth.uid(), p_endpoint, p_p256dh, p_auth, p_user_agent)
  on conflict (user_id, endpoint) do update set p256dh = excluded.p256dh, auth = excluded.auth, user_agent = excluded.user_agent, last_used_at = now() returning id into v_id;
  return v_id;
end; $$;

create function public.process_due_reminders() returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.rounds r set status = 'collecting' where status = 'upcoming' and due_date <= (now() at time zone 'Asia/Kolkata')::date
    and not exists(select 1 from public.rounds previous where previous.chitti_id = r.chitti_id and previous.round_number < r.round_number and previous.status <> 'completed');
  update public.contributions c set status = 'overdue' from public.rounds r where r.id = c.round_id and r.status = 'collecting' and r.due_date < (now() at time zone 'Asia/Kolkata')::date and c.status = 'due';
  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
    select c.member_id, 'contribution.overdue', 'Chitti payment is overdue', 'Open Chitti to review this month''s contribution.', '/chitti/' || r.chitti_id,
      'overdue:' || c.id || ':' || (now() at time zone 'Asia/Kolkata')::date
    from public.contributions c join public.rounds r on r.id = c.round_id where c.status = 'overdue'
    on conflict (user_id, dedupe_key) where dedupe_key is not null do nothing;
end; $$;

create function public.get_app_snapshot() returns jsonb language sql stable security definer set search_path = '' as $$
with me as (
  select p.*, coalesce(ar.role, 'member') role from public.profiles p left join public.app_roles ar on ar.user_id = p.id where p.id = auth.uid()
), my_chittis as (
  select c.* from public.chittis c join public.chitti_members cm on cm.chitti_id = c.id where cm.user_id = auth.uid() and c.archived_at is null
)
select jsonb_build_object(
  'userId', auth.uid(),
  'users', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', display_name, 'email', email, 'phone', phone, 'avatarUri', avatar_url, 'role', role)) from me), '[]'::jsonb),
  'chittis', coalesce((select jsonb_agg(jsonb_build_object(
    'id', c.id, 'name', c.name, 'description', c.description, 'monthlyAmountPaise', c.monthly_amount_paise, 'memberCount', c.member_count,
    'firstDueDate', c.first_due_date, 'dueDay', c.due_day, 'upiId', c.upi_id, 'payeeName', c.payee_name, 'status', c.status,
    'shuffleScheduledAt', c.shuffle_scheduled_at, 'resultHash', (select sr.result_hash from public.shuffle_runs sr where sr.chitti_id = c.id order by sr.run_number desc limit 1), 'createdAt', c.created_at,
    'invitations', case when public.is_chitti_admin(c.id) then coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'name', i.invited_name, 'email', i.invited_email, 'phone', i.invited_phone, 'status', i.status) order by i.created_at) from public.invitations i where i.chitti_id = c.id), '[]'::jsonb) else '[]'::jsonb end,
    'members', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name,
      'email', case when public.is_chitti_admin(c.id) then p.email else '' end, 'phone', case when public.is_chitti_admin(c.id) then p.phone else '' end,
      'avatarUri', p.avatar_url, 'joined', true, 'payoutPosition', cm.payout_position, 'approval', coalesce(sa.status, 'pending'), 'isAdmin', cm.is_admin) order by coalesce(cm.payout_position, 99), p.display_name)
      from public.chitti_members cm join public.profiles p on p.id = cm.user_id
      left join public.shuffle_runs sr on sr.id = (select id from public.shuffle_runs where chitti_id = c.id order by run_number desc limit 1)
      left join public.shuffle_approvals sa on sa.shuffle_run_id = sr.id and sa.member_id = p.id where cm.chitti_id = c.id), '[]'::jsonb),
    'rounds', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'number', r.round_number, 'dueDate', r.due_date, 'recipientMemberId', r.recipient_id,
      'status', r.status, 'payoutStatus', p.status, 'confirmedCount', (select count(*) from public.contributions cc where cc.round_id = r.id and cc.status = 'confirmed'),
      'contributions', coalesce((select jsonb_agg(jsonb_build_object('id', cc.id, 'memberId', cc.member_id, 'status', cc.status,
        'method', case when public.is_chitti_admin(c.id) or cc.member_id = auth.uid() then cc.method else null end,
        'reference', case when public.is_chitti_admin(c.id) or cc.member_id = auth.uid() then cc.reference else null end,
        'submittedAt', cc.submitted_at, 'confirmedAt', cc.confirmed_at)) from public.contributions cc
        where cc.round_id = r.id and (public.is_chitti_admin(c.id) or cc.member_id = auth.uid())), '[]'::jsonb)) order by r.round_number)
      from public.rounds r join public.payouts p on p.round_id = r.id where r.chitti_id = c.id), '[]'::jsonb)
  ) order by c.created_at desc) from my_chittis c), '[]'::jsonb),
  'notifications', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'userId', n.user_id, 'title', n.title, 'message', n.message, 'route', n.route, 'read', n.read_at is not null, 'createdAt', n.created_at) order by n.created_at desc) from public.notifications n where n.user_id = auth.uid()), '[]'::jsonb)
);
$$;

revoke all on function public.create_chitti(jsonb) from public, anon;
revoke all on function public.redeem_invitation(text, uuid) from public, anon;
revoke all on function public.regenerate_invitation(uuid) from public, anon;
revoke all on function public.schedule_shuffle(uuid, timestamptz) from public, anon;
revoke all on function public.run_shuffle(uuid, uuid) from public, anon;
revoke all on function public.respond_to_shuffle(uuid, boolean, text) from public, anon;
revoke all on function public.submit_contribution(uuid, public.payment_method, text) from public, anon;
revoke all on function public.review_contribution(uuid, boolean) from public, anon;
revoke all on function public.confirm_payout(uuid, text) from public, anon;
revoke all on function public.mark_notification_read(uuid) from public, anon;
revoke all on function public.register_push_subscription(text, text, text, text) from public, anon;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.create_chitti(jsonb) to authenticated;
grant execute on function public.redeem_invitation(text, uuid) to authenticated;
grant execute on function public.regenerate_invitation(uuid) to authenticated;
grant execute on function public.schedule_shuffle(uuid, timestamptz) to authenticated;
grant execute on function public.run_shuffle(uuid, uuid) to authenticated;
grant execute on function public.respond_to_shuffle(uuid, boolean, text) to authenticated;
grant execute on function public.submit_contribution(uuid, public.payment_method, text) to authenticated;
grant execute on function public.review_contribution(uuid, boolean) to authenticated;
grant execute on function public.confirm_payout(uuid, text) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.register_push_subscription(text, text, text, text) to authenticated;
grant execute on function public.get_app_snapshot() to authenticated;
revoke all on function public.process_due_reminders() from public, anon, authenticated;

revoke all on all tables in schema public from anon;
grant select on public.profiles, public.app_roles, public.chittis, public.invitations, public.chitti_members,
  public.shuffle_runs, public.shuffle_assignments, public.shuffle_approvals, public.rounds, public.contributions,
  public.payouts, public.notifications, public.push_subscriptions, public.audit_events to authenticated;
grant update(display_name, phone, avatar_url) on public.profiles to authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy avatar_insert_own on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_update_own on storage.objects for update to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_delete_own on storage.objects for delete to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatar_public_read on storage.objects for select to public using (bucket_id = 'avatars');

alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.shuffle_runs;
alter publication supabase_realtime add table public.shuffle_approvals;
alter publication supabase_realtime add table public.rounds;
alter publication supabase_realtime add table public.contributions;

create policy chitti_presence_read on realtime.messages for select to authenticated
using (realtime.topic() ~ '^chitti:[0-9a-f-]{36}:presence$' and public.is_chitti_member(split_part(realtime.topic(), ':', 2)::uuid));
create policy chitti_presence_write on realtime.messages for insert to authenticated
with check (realtime.topic() ~ '^chitti:[0-9a-f-]{36}:presence$' and public.is_chitti_member(split_part(realtime.topic(), ':', 2)::uuid));

commit;
