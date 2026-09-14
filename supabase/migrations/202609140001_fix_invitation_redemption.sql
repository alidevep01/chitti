-- PostgreSQL resolves string literals in this CASE expression as text. Cast each
-- branch explicitly so the result can be stored in the chitti_status enum.
create or replace function public.redeem_invitation(p_token text default null, p_invitation_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.invitations;
  v_email text;
  v_joined int;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_email := lower(coalesce(auth.jwt()->>'email', ''));

  select *
  into v_invite
  from public.invitations
  where (p_token is not null and token_hash = extensions.digest(p_token, 'sha256'))
     or (p_invitation_id is not null and id = p_invitation_id)
  for update;

  if v_invite.id is null or v_invite.status <> 'pending' or v_invite.expires_at < now() then
    raise exception 'Invitation is invalid or expired';
  end if;
  if lower(v_invite.invited_email) <> v_email then
    raise exception 'Sign in with the invited Google email';
  end if;

  update public.profiles
  set phone = case when btrim(phone) = '' then v_invite.invited_phone else phone end
  where id = auth.uid();

  insert into public.chitti_members(chitti_id, user_id)
  values (v_invite.chitti_id, auth.uid());

  update public.invitations
  set status = 'accepted', accepted_by = auth.uid(), accepted_at = now()
  where id = v_invite.id;

  select count(*)
  into v_joined
  from public.chitti_members
  where chitti_id = v_invite.chitti_id;

  update public.chittis
  set status = case
    when v_joined = member_count then 'ready'::public.chitti_status
    else 'inviting'::public.chitti_status
  end
  where id = v_invite.chitti_id;

  insert into public.notifications(user_id, kind, title, message, route, dedupe_key)
  select admin_id, 'invitation.accepted', v_invite.invited_name || ' joined',
    'A member accepted the invitation.', '/chitti/' || v_invite.chitti_id,
    'joined:' || v_invite.id
  from public.chittis
  where id = v_invite.chitti_id;

  insert into public.audit_events(actor_id, chitti_id, action, entity_type, entity_id)
  values (auth.uid(), v_invite.chitti_id, 'invitation.accepted', 'invitation', v_invite.id::text);

  return v_invite.chitti_id;
end;
$$;

revoke all on function public.redeem_invitation(text, uuid) from public, anon;
grant execute on function public.redeem_invitation(text, uuid) to authenticated;
