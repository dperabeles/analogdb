alter table public.cameras
  add column if not exists mount text,
  add column if not exists supports_interchangeable_lenses boolean not null default true;

create table if not exists public.lenses (
  id bigint generated always as identity primary key,
  maker text not null,
  model text not null,
  mount text,
  show_in_quick_mode boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  unique (owner_user_id, maker, model, mount)
);

alter table public.rolls
  add column if not exists lens_id bigint references public.lenses(id) on delete set null;

create index if not exists lenses_owner_user_id_idx
on public.lenses(owner_user_id);

create index if not exists lenses_owner_mount_idx
on public.lenses(owner_user_id, mount);

create index if not exists rolls_lens_id_idx
on public.rolls(lens_id);

drop trigger if exists lenses_touch on public.lenses;
create trigger lenses_touch
before update on public.lenses
for each row execute function public.touch_updated_at();

grant select, insert, update, delete on public.lenses to authenticated;

alter table public.lenses enable row level security;

drop policy if exists lenses_owner_select on public.lenses;
create policy lenses_owner_select
on public.lenses
for select
to authenticated
using (owner_user_id = auth.uid());

drop policy if exists lenses_owner_insert on public.lenses;
create policy lenses_owner_insert
on public.lenses
for insert
to authenticated
with check (owner_user_id = auth.uid());

drop policy if exists lenses_owner_update on public.lenses;
create policy lenses_owner_update
on public.lenses
for update
to authenticated
using (owner_user_id = auth.uid())
with check (owner_user_id = auth.uid());

drop policy if exists lenses_owner_delete on public.lenses;
create policy lenses_owner_delete
on public.lenses
for delete
to authenticated
using (owner_user_id = auth.uid());

create or replace view public.rolls_flat
with (security_invoker = true)
as
select
  r.id,
  r.code as "#",
  fs.type as "FILM TYPE",
  r.format as "FORMAT",
  case
    when r.fresh is null then null
    when r.fresh then 'FRESH'
    else 'EXPIRED'
  end as "EXP/FRESH",
  fs.name as "FILM STOCK",
  fs.manufacturer as "MANUFACTURER",
  fs.iso as "ISO",
  r.exp_count as "EXP",
  c.maker as "MAKER",
  c.model as "MODEL NAME",
  c.format as "C. FORMAT",
  c.type as "C. TYPE",
  c.mount as "C. MOUNT",
  coalesce(nullif(trim(concat_ws(' ', l.maker, l.model)), ''), r.lens) as "LENS",
  l.mount as "LENS MOUNT",
  array_to_string(r.locations, ', ') as "LOCATIONS",
  array_to_string(r.photo_types, ', ') as "PHOTO TYPE",
  array_to_string(r.tags, ', ') as "TAGS",
  r.iso_pushed as "ISO @",
  to_char(r.started::timestamptz, 'YYYY-MM-DD') as "STARTED",
  to_char(r.finished::timestamptz, 'YYYY-MM-DD') as "FINISHED",
  r.exp_taken as "# EXP",
  r.push_pull as "PUSH/PULL",
  dl.name as "DEV",
  sl.name as "SCAN",
  r.status as "STATUS",
  r.rating as "RATING",
  r.notes as "NOTES",
  r.updated_at,
  coalesce(re_stats.frame_settings_count, 0)::integer as "FRAME SETTINGS"
from public.rolls r
left join public.film_stocks fs on fs.id = r.film_stock_id
left join public.cameras c on c.id = r.camera_id
left join public.lenses l on l.id = r.lens_id
left join public.labs dl on dl.id = r.dev_lab_id
left join public.labs sl on sl.id = r.scan_lab_id
left join lateral (
  select count(*) filter (
    where re.apertura is not null
       or re.shutter_speed is not null
       or coalesce(re.tripie, false)
       or coalesce(re.filtros, false)
       or coalesce(re.flash, false)
       or coalesce(re.multiple_exposures, false)
       or nullif(trim(re.notes), '') is not null
  ) as frame_settings_count
  from public.roll_exposures re
  where re.roll_id = r.id
) re_stats on true;

grant select on public.rolls_flat to authenticated;
