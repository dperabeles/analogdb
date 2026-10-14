-- Private, owner-only profile content and personal annual film goals.
-- No usernames, public profile, awards or social access are introduced here.
create table public.profile_preferences (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  alias text check (alias is null or (char_length(alias) between 1 and 40 and alias = btrim(alias))),
  bio text check (bio is null or (char_length(bio) between 1 and 160 and bio = btrim(bio))),
  favorite_film_stock_id bigint references public.film_stocks(id) on delete set null,
  favorite_camera_id bigint references public.cameras(id) on delete set null,
  favorite_lens_id bigint references public.lenses(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.annual_film_goals (
  user_id uuid not null references public.profiles(user_id) on delete cascade,
  year integer not null check (year between 2000 and 2100),
  target_rolls integer not null check (target_rolls between 1 and 9999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, year)
);

-- RLS alone is insufficient for favourites: the referenced gear must belong
-- to this profile, even if catalogue/read policies change in the future.
create function public.validate_profile_favorites()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.favorite_camera_id is not null and not exists (
    select 1 from public.cameras c
    where c.id = new.favorite_camera_id and c.owner_user_id = new.user_id
  ) then
    raise exception 'Favorite camera must belong to profile owner' using errcode = '23514';
  end if;
  if new.favorite_lens_id is not null and not exists (
    select 1 from public.lenses l
    where l.id = new.favorite_lens_id and l.owner_user_id = new.user_id
  ) then
    raise exception 'Favorite lens must belong to profile owner' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger validate_profile_favorites_before_write
before insert or update on public.profile_preferences
for each row execute function public.validate_profile_favorites();

create function public.touch_private_profile_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger profile_preferences_updated_at
before update on public.profile_preferences
for each row execute function public.touch_private_profile_updated_at();
create trigger annual_film_goals_updated_at
before update on public.annual_film_goals
for each row execute function public.touch_private_profile_updated_at();

alter table public.profile_preferences enable row level security;
alter table public.annual_film_goals enable row level security;
revoke all on public.profile_preferences, public.annual_film_goals from anon, public;
grant select, insert, update on public.profile_preferences to authenticated;
grant select, insert, update, delete on public.annual_film_goals to authenticated;

create policy profile_preferences_select_own on public.profile_preferences
  for select to authenticated using (user_id = (select auth.uid()));
create policy profile_preferences_insert_own on public.profile_preferences
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy profile_preferences_update_own on public.profile_preferences
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy annual_film_goals_select_own on public.annual_film_goals
  for select to authenticated using (user_id = (select auth.uid()));
create policy annual_film_goals_insert_own on public.annual_film_goals
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy annual_film_goals_update_own on public.annual_film_goals
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy annual_film_goals_delete_own on public.annual_film_goals
  for delete to authenticated using (user_id = (select auth.uid()));

comment on table public.profile_preferences is
  'Private owner-selected profile content. Never expose this table for social profile reads.';
comment on table public.annual_film_goals is
  'Private per-calendar-year targets for distinct rolls finished in that year.';
notify pgrst, 'reload schema';
