begin;

alter function public.get_app_snapshot() rename to get_app_snapshot_without_pending_invitations;

create function public.get_app_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_snapshot jsonb;
  v_email text;
  v_pending jsonb;
begin
  v_snapshot := public.get_app_snapshot_without_pending_invitations();
  select lower(profile.email) into v_email
  from public.profiles profile
  where profile.id = auth.uid();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', invitation.id,
    'chittiId', chitti.id,
    'chittiName', chitti.name,
    'invitedName', invitation.invited_name,
    'monthlyAmountPaise', chitti.monthly_amount_paise,
    'memberCount', chitti.member_count,
    'administratorName', administrator.display_name,
    'expiresAt', invitation.expires_at,
    'createdAt', invitation.created_at
  ) order by invitation.created_at desc), '[]'::jsonb)
  into v_pending
  from public.invitations invitation
  join public.chittis chitti on chitti.id = invitation.chitti_id
  join public.profiles administrator on administrator.id = chitti.admin_id
  where lower(invitation.invited_email) = v_email
    and invitation.status = 'pending'
    and invitation.expires_at > now()
    and chitti.status not in ('completed', 'cancelled');

  return v_snapshot || jsonb_build_object('pendingInvitations', v_pending);
end;
$$;

revoke all on function public.get_app_snapshot() from public, anon;
grant execute on function public.get_app_snapshot() to authenticated;

commit;
