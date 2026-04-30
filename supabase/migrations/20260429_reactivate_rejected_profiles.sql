create or replace function public.admin_set_profile_status(p_target_user_id uuid, p_status text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  updated_profile public.profiles;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  if p_status not in ('pending', 'approved', 'rejected') then
    raise exception 'invalid status';
  end if;

  update public.profiles
  set
    status = p_status,
    approved_at = case when p_status = 'approved' then now() else null end,
    approved_by = case when p_status = 'approved' then actor_id else null end,
    rejected_at = case when p_status = 'rejected' then now() else null end,
    rejected_by = case when p_status = 'rejected' then actor_id else null end
  where user_id = p_target_user_id
  returning * into updated_profile;

  if not found then
    raise exception 'profile not found';
  end if;

  return updated_profile;
end;
$$;
