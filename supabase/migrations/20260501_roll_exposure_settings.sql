create table if not exists public.roll_exposures (
  id uuid primary key default gen_random_uuid(),
  roll_id bigint not null references public.rolls(id) on delete cascade,
  frame_number integer not null check (frame_number > 0),
  apertura text,
  shutter_speed text,
  tripie boolean,
  filtros boolean,
  flash boolean,
  luz_natural boolean,
  multiple_exposures boolean,
  notes text,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (roll_id, frame_number)
);

create index if not exists roll_exposures_roll_id_idx
on public.roll_exposures(roll_id);

create index if not exists roll_exposures_roll_frame_idx
on public.roll_exposures(roll_id, frame_number);

drop trigger if exists roll_exposures_touch on public.roll_exposures;
create trigger roll_exposures_touch
before update on public.roll_exposures
for each row
execute function public.touch_updated_at();

grant select, insert, update, delete on public.roll_exposures to authenticated;

alter table public.roll_exposures enable row level security;

drop policy if exists roll_exposures_owner_select on public.roll_exposures;
create policy roll_exposures_owner_select
on public.roll_exposures
for select
to public
using (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

drop policy if exists roll_exposures_owner_insert on public.roll_exposures;
create policy roll_exposures_owner_insert
on public.roll_exposures
for insert
to public
with check (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

drop policy if exists roll_exposures_owner_update on public.roll_exposures;
create policy roll_exposures_owner_update
on public.roll_exposures
for update
to public
using (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
)
with check (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

drop policy if exists roll_exposures_owner_delete on public.roll_exposures;
create policy roll_exposures_owner_delete
on public.roll_exposures
for delete
to public
using (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

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
  r.lens as "LENS",
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
left join public.labs dl on dl.id = r.dev_lab_id
left join public.labs sl on sl.id = r.scan_lab_id
left join lateral (
  select count(*) filter (
    where re.apertura is not null
       or re.shutter_speed is not null
       or coalesce(re.tripie, false)
       or coalesce(re.filtros, false)
       or coalesce(re.flash, false)
       or coalesce(re.luz_natural, false)
       or coalesce(re.multiple_exposures, false)
       or re.notes is not null
  ) as frame_settings_count
  from public.roll_exposures re
  where re.roll_id = r.id
) re_stats on true;

grant select on public.rolls_flat to authenticated;
