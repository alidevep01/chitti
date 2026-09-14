begin;

create function public.get_admin_contacts()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
select case when public.is_admin() then coalesce((
  with invited as (
    select
      lower(invitation.invited_email) as email,
      (array_agg(invitation.invited_name order by invitation.created_at desc))[1] as invited_name,
      (array_agg(invitation.invited_phone order by invitation.created_at desc))[1] as invited_phone,
      max(invitation.created_at) as last_invited_at,
      count(*)::int as times_invited
    from public.invitations invitation
    join public.chittis chitti on chitti.id = invitation.chitti_id
    where chitti.admin_id = auth.uid()
    group by lower(invitation.invited_email)
  )
  select jsonb_agg(jsonb_build_object(
    'name', coalesce(nullif(profile.display_name, ''), invited.invited_name),
    'email', invited.email,
    'phone', coalesce(nullif(profile.phone, ''), invited.invited_phone),
    'avatarUri', profile.avatar_url,
    'timesInvited', invited.times_invited,
    'lastInvitedAt', invited.last_invited_at
  ) order by coalesce(nullif(profile.display_name, ''), invited.invited_name))
  from invited
  left join public.profiles profile on lower(profile.email) = invited.email
), '[]'::jsonb) else '[]'::jsonb end;
$$;

revoke all on function public.get_admin_contacts() from public, anon;
grant execute on function public.get_admin_contacts() to authenticated;

commit;
