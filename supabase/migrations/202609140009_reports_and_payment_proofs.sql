begin;

alter table public.contributions
  add column proof_path text
  check (proof_path is null or char_length(proof_path) <= 500);

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create function public.can_read_payment_proof(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner text := split_part(object_name, '/', 1);
  v_contribution text := split_part(object_name, '/', 2);
begin
  if auth.uid() is null then
    return false;
  end if;
  if v_owner = auth.uid()::text then
    return true;
  end if;
  if v_contribution !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$' then
    return false;
  end if;
  return exists (
    select 1
    from public.contributions contribution
    join public.rounds round_item on round_item.id = contribution.round_id
    where contribution.id = v_contribution::uuid
      and contribution.member_id::text = v_owner
      and public.is_chitti_admin(round_item.chitti_id)
  );
end;
$$;

create policy payment_proof_insert_own
on storage.objects for insert to authenticated
with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy payment_proof_update_own
on storage.objects for update to authenticated
using (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text)
with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy payment_proof_delete_own
on storage.objects for delete to authenticated
using (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy payment_proof_private_read
on storage.objects for select to authenticated
using (bucket_id = 'payment-proofs' and public.can_read_payment_proof(name));

create function public.submit_contribution(
  p_round_id uuid,
  p_method public.payment_method,
  p_reference text,
  p_proof_path text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.rounds;
  v_contribution_id uuid;
  v_catchup boolean;
begin
  select * into v_round from public.rounds where id = p_round_id;
  if v_round.id is null or not public.is_chitti_member(v_round.chitti_id) then
    raise exception 'This round is unavailable';
  end if;

  select contribution.id,
    exists(
      select 1 from public.payout_adjustments adjustment
      where adjustment.contribution_id = contribution.id
        and adjustment.status = 'awaiting_contribution'
    )
  into v_contribution_id, v_catchup
  from public.contributions contribution
  where contribution.round_id = p_round_id
    and contribution.member_id = auth.uid();

  if v_round.status <> 'collecting' and not coalesce(v_catchup, false) then
    raise exception 'This round is not open';
  end if;
  if p_proof_path is not null and (
    char_length(p_proof_path) > 500
    or split_part(p_proof_path, '/', 1) <> auth.uid()::text
    or split_part(p_proof_path, '/', 2) <> v_contribution_id::text
  ) then
    raise exception 'Invalid payment proof path';
  end if;

  update public.contributions
  set status = 'submitted',
      method = p_method,
      reference = nullif(p_reference, ''),
      proof_path = coalesce(nullif(p_proof_path, ''), proof_path),
      submitted_at = now(),
      confirmed_at = null,
      confirmed_on_time = null,
      reviewed_by = null
  where id = v_contribution_id
    and status in ('due', 'rejected', 'overdue');
  if not found then
    raise exception 'Contribution cannot be submitted';
  end if;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id, detail)
  values (
    auth.uid(), v_round.chitti_id, 'contribution.submitted', 'contribution', v_contribution_id::text,
    jsonb_build_object('catchup', coalesce(v_catchup, false), 'has_proof', p_proof_path is not null)
  );

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select admin_id,
    'contribution.submitted',
    case when v_catchup then 'Catch-up payment awaiting review' else 'Payment awaiting review' end,
    'A member marked a contribution as paid' || case when p_proof_path is not null then ' and attached a photo.' else '.' end,
    '/chitti/' || v_round.chitti_id,
    'submitted:' || v_contribution_id
  from public.chittis where id = v_round.chitti_id
  on conflict (user_id, dedupe_key) where dedupe_key is not null do update
    set title = excluded.title,
        message = excluded.message,
        read_at = null,
        created_at = now();
end;
$$;

alter function public.get_app_snapshot() rename to get_app_snapshot_without_payment_proofs;

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
  v_snapshot := public.get_app_snapshot_without_payment_proofs();
  return jsonb_set(
    v_snapshot,
    '{chittis}',
    coalesce((
      select jsonb_agg(
        chitti || jsonb_build_object(
          'rounds', coalesce((
            select jsonb_agg(
              round_item || jsonb_build_object(
                'contributions', coalesce((
                  select jsonb_agg(
                    contribution || jsonb_build_object(
                      'proofPath', coalesce(to_jsonb(con.proof_path), 'null'::jsonb)
                    ) order by contribution_order
                  )
                  from jsonb_array_elements(round_item->'contributions') with ordinality
                    as contribution_items(contribution, contribution_order)
                  join public.contributions con on con.id = (contribution->>'id')::uuid
                ), '[]'::jsonb)
              ) order by round_order
            )
            from jsonb_array_elements(chitti->'rounds') with ordinality
              as round_items(round_item, round_order)
          ), '[]'::jsonb)
        ) order by chitti_order
      )
      from jsonb_array_elements(v_snapshot->'chittis') with ordinality
        as chitti_items(chitti, chitti_order)
    ), '[]'::jsonb),
    true
  );
end;
$$;

create function public.get_reports()
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
    coalesce(sum(chitti.monthly_amount_paise) filter (where contribution.status = 'confirmed'), 0)::bigint as confirmed_amount,
    coalesce(sum(chitti.monthly_amount_paise) filter (
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
      'monthlyAmountPaise', chitti.monthly_amount_paise,
      'totalAmountPaise', chitti.monthly_amount_paise * chitti.member_count,
      'startDate', chitti.start_date,
      'endDate', chitti.end_date,
      'payoutPosition', membership.payout_position,
      'payoutDate', payout_round.due_date,
      'payoutStatus', payout.status,
      'onTimePayments', chitti_stats.on_time,
      'latePayments', chitti_stats.late,
      'missedDueDates', chitti_stats.missed,
      'confirmedAmountPaise', chitti_stats.confirmed_amount,
      'overdueAmountPaise', chitti_stats.overdue_amount
    ) order by chitti.created_at desc)
    from public.chitti_members membership
    join public.chittis chitti on chitti.id = membership.chitti_id
    left join public.rounds payout_round
      on payout_round.chitti_id = chitti.id and payout_round.recipient_id = report_user.user_id
    left join public.payouts payout on payout.round_id = payout_round.id
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
        coalesce(sum(chitti.monthly_amount_paise) filter (where contribution.status = 'confirmed'), 0)::bigint as confirmed_amount,
        coalesce(sum(chitti.monthly_amount_paise) filter (
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

revoke all on function public.can_read_payment_proof(text) from public, anon;
grant execute on function public.can_read_payment_proof(text) to authenticated;
revoke all on function public.submit_contribution(uuid, public.payment_method, text, text) from public, anon;
grant execute on function public.submit_contribution(uuid, public.payment_method, text, text) to authenticated;
revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;
revoke all on function public.get_reports() from public, anon;
grant execute on function public.get_reports() to authenticated;

commit;
