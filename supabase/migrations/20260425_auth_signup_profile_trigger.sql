begin;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  requested_display_name text;
begin
  requested_display_name := btrim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  if char_length(requested_display_name) < 3 then
    requested_display_name := btrim(split_part(coalesce(new.email, 'user'), '@', 1));
  end if;

  if char_length(requested_display_name) < 3 then
    requested_display_name := 'User';
  end if;

  requested_display_name := left(requested_display_name, 20);

  insert into public.profiles (
    user_id,
    email,
    display_name,
    status,
    approved_at,
    approved_by,
    rejected_at,
    rejected_by
  )
  values (
    new.id,
    new.email,
    requested_display_name,
    'pending',
    null,
    null,
    null,
    null
  )
  on conflict (user_id) do nothing;

  insert into public.user_roles (
    user_id,
    role,
    is_founder,
    granted_by
  )
  values (
    new.id,
    'user',
    false,
    null
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_create_profile on auth.users;
create trigger on_auth_user_created_create_profile
after insert on auth.users
for each row
execute function public.handle_new_auth_user();

insert into public.profiles (
  user_id,
  email,
  display_name,
  status,
  approved_at,
  approved_by,
  rejected_at,
  rejected_by
)
select
  u.id,
  u.email,
  left(
    case
      when char_length(btrim(coalesce(u.raw_user_meta_data ->> 'display_name', ''))) >= 3
        then btrim(u.raw_user_meta_data ->> 'display_name')
      when char_length(btrim(split_part(coalesce(u.email, 'user'), '@', 1))) >= 3
        then btrim(split_part(u.email, '@', 1))
      else 'User'
    end,
    20
  ),
  'pending',
  null,
  null,
  null,
  null
from auth.users u
where not exists (
  select 1
  from public.profiles p
  where p.user_id = u.id
);

insert into public.user_roles (
  user_id,
  role,
  is_founder,
  granted_by
)
select
  u.id,
  'user',
  false,
  null
from auth.users u
where not exists (
  select 1
  from public.user_roles r
  where r.user_id = u.id
);

commit;
