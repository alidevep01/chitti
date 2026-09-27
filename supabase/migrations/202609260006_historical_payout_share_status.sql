begin;

create or replace function public.create_round_payout_share()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chitti public.chittis;
  v_member public.chitti_members;
  v_pot bigint;
  v_amount bigint;
  v_allocated bigint := 0;
  v_round_share_id uuid;
  v_status public.payout_status;
begin
  select * into v_chitti from public.chittis where id = new.chitti_id;
  v_pot := v_chitti.monthly_amount_paise * v_chitti.member_count;
  v_status := case
    when new.status = 'completed' then 'paid'::public.payout_status
    when new.status = 'ready_for_payout' then 'ready'::public.payout_status
    else 'blocked'::public.payout_status
  end;

  for v_member in
    select * from public.chitti_members
    where chitti_id = new.chitti_id and payout_position = new.round_number
    order by is_admin desc, joined_at, user_id
  loop
    v_amount := floor(v_pot * v_member.contribution_share_bps / 10000.0)::bigint;
    insert into public.round_payout_shares(
      round_id, recipient_id, amount_paise, share_bps, status, paid_at
    ) values (
      new.id, v_member.user_id, v_amount, v_member.contribution_share_bps,
      v_status, case when v_status = 'paid' then now() else null end
    ) returning id into v_round_share_id;
    v_allocated := v_allocated + v_amount;
  end loop;

  if v_allocated <> v_pot and v_round_share_id is not null then
    update public.round_payout_shares
    set amount_paise = amount_paise + (v_pot - v_allocated)
    where id = v_round_share_id;
  end if;
  return new;
end;
$$;

commit;
