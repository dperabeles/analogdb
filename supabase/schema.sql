-- ═══════════════════════════════════════════════════════════════
-- analogdb — Supabase schema v1
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query → Run
-- ═══════════════════════════════════════════════════════════════

-- Limpieza por si re-corres (borra todo, úsalo sólo en setup inicial)
drop view  if exists rolls_flat      cascade;
drop table if exists rolls           cascade;
drop table if exists film_stocks     cascade;
drop table if exists cameras         cascade;
drop table if exists labs            cascade;

-- ───────────────────────────────────────────────────────────────
-- Catálogo de fabricantes y stocks
-- ───────────────────────────────────────────────────────────────
create table film_stocks (
  id            bigint generated always as identity primary key,
  manufacturer  text not null,
  name          text not null,
  iso           int,
  type          text check (type in ('COLOR','B/W','SLIDE')),
  in_catalog    boolean default true,    -- true = del catálogo Wikipedia; false = agregado manualmente
  unique (manufacturer, name)
);

-- ───────────────────────────────────────────────────────────────
-- Cámaras únicas (una fila por combinación maker+model)
-- ───────────────────────────────────────────────────────────────
create table cameras (
  id      bigint generated always as identity primary key,
  maker   text,
  model   text,
  format  text,    -- '35mm' | '120' | 'Super8'
  type    text,    -- 'SLR' | 'Point & Shoot' | 'Rangefinder' | etc.
  unique (maker, model)
);

-- ───────────────────────────────────────────────────────────────
-- Laboratorios (revelado y scan — mismo catálogo)
-- ───────────────────────────────────────────────────────────────
create table labs (
  id    bigint generated always as identity primary key,
  name  text unique not null
);

-- ───────────────────────────────────────────────────────────────
-- Rollos
-- ───────────────────────────────────────────────────────────────
create table rolls (
  id             bigint generated always as identity primary key,
  code           text unique not null,                  -- "R001", "R093", etc.
  film_stock_id  bigint references film_stocks(id) on delete set null,
  iso_pushed     int,                                   -- ISO @ (si pusheaste/pulleaste)
  format         int,                                   -- 35 | 120
  exp_count      int,                                   -- # de exposiciones del carrete (24/36)
  exp_taken      int,                                   -- # EXP (disparadas)
  fresh          boolean,                               -- TRUE=FRESH, FALSE=EXPIRED
  push_pull      text,                                  -- "+1" | "-2" | "-"
  camera_id      bigint references cameras(id) on delete set null,
  lens           text,
  locations      text[] default '{}',                   -- array de lugares
  photo_types    text[] default '{}',                   -- array de tipos de foto
  started        date,
  finished       date,
  status         text,                                  -- 'In Camera' | 'To Develop' | 'In Development' | 'Done'
  dev_lab_id     bigint references labs(id) on delete set null,
  scan_lab_id    bigint references labs(id) on delete set null,
  rating         int check (rating between 0 and 5),
  notes          text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

create index on rolls(status);
create index on rolls(started);
create index on rolls(film_stock_id);
create index on rolls(camera_id);

-- Auto-update updated_at
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger rolls_touch before update on rolls
  for each row execute function touch_updated_at();

-- ───────────────────────────────────────────────────────────────
-- Vista "plana" — devuelve cada rollo con los campos denormalizados
-- en el mismo formato que el JSON actual del HTML, para minimizar
-- cambios en el front.
-- ───────────────────────────────────────────────────────────────
create view rolls_flat as
select
  r.id,
  r.code                                              as "#",
  fs.type                                             as "FILM TYPE",
  r.format                                            as "FORMAT",
  case when r.fresh is null then null
       when r.fresh then 'FRESH' else 'EXPIRED' end   as "EXP/FRESH",
  fs.name                                             as "FILM STOCK",
  fs.manufacturer                                     as "MANUFACTURER",
  fs.iso                                              as "ISO",
  r.exp_count                                         as "EXP",
  c.maker                                             as "MAKER",
  c.model                                             as "MODEL NAME",
  c.format                                            as "C. FORMAT",
  c.type                                              as "C. TYPE",
  r.lens                                              as "LENS",
  array_to_string(r.locations, ', ')                  as "LOCATIONS",
  array_to_string(r.photo_types, ', ')                as "PHOTO TYPE",
  r.iso_pushed                                        as "ISO @",
  to_char(r.started,  'YYYY-MM-DD')                   as "STARTED",
  to_char(r.finished, 'YYYY-MM-DD')                   as "FINISHED",
  r.exp_taken                                         as "# EXP",
  r.push_pull                                         as "PUSH/PULL",
  dl.name                                             as "DEV",
  sl.name                                             as "SCAN",
  r.status                                            as "STATUS",
  r.rating                                            as "RATING",
  r.notes                                             as "NOTES",
  r.updated_at
from rolls r
left join film_stocks fs on fs.id = r.film_stock_id
left join cameras     c  on c.id  = r.camera_id
left join labs        dl on dl.id = r.dev_lab_id
left join labs        sl on sl.id = r.scan_lab_id;

-- ───────────────────────────────────────────────────────────────
-- RLS: por ahora DESHABILITADO para permitir migración inicial.
-- Una vez migrados los datos, lo habilitamos + auth por email.
-- ───────────────────────────────────────────────────────────────
alter table rolls        disable row level security;
alter table film_stocks  disable row level security;
alter table cameras      disable row level security;
alter table labs         disable row level security;

-- Listo. Deberías ver 4 tablas + 1 vista en Database → Tables.
