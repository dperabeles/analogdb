-- Catálogo de cámaras, Fase 3 (Diego, 19-nov): monturas, modelos de cámara
-- compartidos y moderados como los films, y la cámara de cada usuario que
-- sigue a su modelo (sin alias).
--
-- · Las cámaras que ya existen no se tocan: ninguna recibe modelo aquí.
-- · Una propuesta pendiente o rechazada la ven solo su autor y el admin,
--   también al apuntar una cámara a ella.
-- · El vocabulario (tipo, formato, cuadro) es una sola lista en el servidor,
--   la misma que escribe la app.

-- ── Vocabulario ───────────────────────────────────────────────────────────

create function app_private.camera_type_ok(p_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_type is null or p_type in (
    'SLR', 'Rangefinder', 'TLR', 'P&S', 'Folding', 'Vista / Gran formato',
    'Cine', 'Instantánea', 'Caja', 'Half-frame', 'Otro')
$$;

create function app_private.camera_format_ok(p_format text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_format is null or p_format in (
    '35mm', '120', '220', '620', '127', '126', '110', 'APS', 'Super8', '16mm',
    'Large Format', 'Instax Mini', 'Instax Wide', 'Instax Square',
    'Polaroid 600', 'Polaroid SX-70', 'Polaroid i-Type')
$$;

-- Los cuadros posibles de un formato; null cuando el formato no tiene.
create function app_private.camera_frame_sizes(p_format text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case
    when p_format in ('120', '220', '620')
      then array['6x4.5', '6x6', '6x7', '6x8', '6x9', '6x12', '6x17']
    when p_format = 'Large Format' then array['4x5', '5x7', '8x10']
  end
$$;

create function app_private.camera_frame_ok(p_format text, p_frame text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_frame is null
      or coalesce(p_frame = any (app_private.camera_frame_sizes(p_format)), false)
$$;

create function app_private.camera_frames_ok(p_format text, p_frames text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_frames is null
      or not exists (select 1 from unnest(p_frames) f
                      where f is null or not app_private.camera_frame_ok(p_format, f))
$$;

-- El nombre de un modelo escrito de varias formas tiene una sola clave
-- («AE-1» = «ae1»), como los fabricantes.
create function app_private.camera_model_key(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select app_private.manufacturer_key(p_name)
$$;

-- ── Monturas ──────────────────────────────────────────────────────────────

create table public.lens_mounts (
  id bigint generated always as identity primary key,
  name text not null check (btrim(name) <> '' and length(name) <= 60),
  status text not null default 'approved' check (status in ('approved', 'merged')),
  merged_into bigint references public.lens_mounts(id),
  created_at timestamptz not null default now(),
  constraint lens_mounts_merged_has_target check ((status = 'merged') = (merged_into is not null))
);
create unique index lens_mounts_approved_key
  on public.lens_mounts (app_private.manufacturer_key(name)) where status = 'approved';
alter table public.lens_mounts enable row level security;
create policy lens_mounts_select on public.lens_mounts
for select to authenticated using (true);
revoke all on public.lens_mounts from anon, authenticated;
grant select on public.lens_mounts to authenticated;

-- ── Modelos de cámara ─────────────────────────────────────────────────────

create table public.camera_models (
  id bigint generated always as identity primary key,
  manufacturer_id bigint not null references public.manufacturers(id),
  name text not null check (btrim(name) <> '' and length(name) <= 120),
  type text check (app_private.camera_type_ok(type)),
  format text check (app_private.camera_format_ok(format)),
  frame_sizes text[] not null default '{}',
  mount_id bigint references public.lens_mounts(id),
  interchangeable boolean,
  year_from integer check (year_from between 1839 and 2100),
  year_to integer check (year_to between 1839 and 2100),
  -- De dónde salió: wikidata, canon, nikon, camerahub, curada, usuario…
  source text not null default 'usuario' check (btrim(source) <> ''),
  source_ref text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'merged')),
  merged_into bigint references public.camera_models(id),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  constraint camera_models_frames check (app_private.camera_frames_ok(format, frame_sizes)),
  constraint camera_models_years check (year_to is null or year_from is null or year_to >= year_from),
  constraint camera_models_merged_has_target check ((status = 'merged') = (merged_into is not null))
);
create unique index camera_models_approved_key
  on public.camera_models (manufacturer_id, app_private.camera_model_key(name))
  where status = 'approved';
create unique index camera_models_own_key
  on public.camera_models (created_by, manufacturer_id, app_private.camera_model_key(name))
  where status in ('pending', 'rejected');
create index camera_models_manufacturer_idx on public.camera_models (manufacturer_id);
create index camera_models_merged_into_idx on public.camera_models (merged_into);
create index camera_models_mount_idx on public.camera_models (mount_id);

alter table public.camera_models enable row level security;
-- Como los films: el catálogo aprobado para todos; lo propuesto, solo para
-- quien lo propuso.
create policy camera_models_select on public.camera_models
for select to authenticated
using (
  status = 'approved'
  or (created_by = (select auth.uid()) and status in ('pending', 'rejected'))
  or public.app_is_admin((select auth.uid()))
);
revoke all on public.camera_models from anon, authenticated;
grant select on public.camera_models to authenticated;

-- ── La cámara de cada usuario sigue a su modelo ───────────────────────────

alter table public.cameras
  add column camera_model_id bigint references public.camera_models(id) on delete set null;
create index cameras_camera_model_idx on public.cameras (camera_model_id);

-- Corre antes que los demás disparadores de cámaras (orden alfabético).
-- Copia del modelo el nombre canónico y sus datos; el cuadro, solo uno que el
-- modelo admite. Un modelo que el dueño no puede ver da el mismo error que
-- uno que no existe.
create function app_private.cameras_follow_model()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_model public.camera_models;
  v_maker text;
  v_mount text;
begin
  if new.camera_model_id is null then
    return new;
  end if;
  select m.* into v_model from public.camera_models m
   where m.id = new.camera_model_id
     and (m.status = 'approved'
          or (m.created_by = new.owner_user_id and m.status in ('pending', 'rejected')));
  if v_model.id is null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select name into v_maker from public.manufacturers where id = v_model.manufacturer_id;
  select name into v_mount from public.lens_mounts where id = v_model.mount_id;

  new.maker := v_maker;
  new.model := v_model.name;
  new.type := v_model.type;
  new.format := v_model.format;
  new.mount := v_mount;
  new.supports_interchangeable_lenses :=
    coalesce(v_model.interchangeable, new.supports_interchangeable_lenses);
  if cardinality(v_model.frame_sizes) = 0 then
    new.frame_size := null;
  elsif new.frame_size is null or not (new.frame_size = any (v_model.frame_sizes)) then
    new.frame_size := v_model.frame_sizes[1];
  end if;
  return new;
end;
$$;
revoke all on function app_private.cameras_follow_model() from public, anon, authenticated;

create trigger cameras_aa_follow_model
before insert or update on public.cameras
for each row execute function app_private.cameras_follow_model();

-- El nombre canónico del catálogo se respeta tal cual («KMZ»); el texto libre
-- se normaliza como siempre.
create or replace function public.gear_normalize_camera()
 returns trigger
 language plpgsql
as $function$
begin
  if new.camera_model_id is null then
    new.maker := public.normalize_gear_maker(new.maker);
  end if;
  new.match_key := public.gear_match_key(new.maker, new.model);
  return new;
end;
$function$;

-- El cuadro vale en todo formato que tenga cuadros (120, 220, 620, gran
-- formato), no solo en 120. Escribir un cuadro como formato sigue siendo 120.
create or replace function app_private.cameras_frame_size_only_120()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if new.format in ('6x4.5', '6x6', '6x7', '6x8', '6x9', '6x12', '6x17') then
    new.frame_size := new.format;
    new.format := '120';
  elsif app_private.camera_frame_sizes(new.format) is null then
    new.frame_size := null;
  end if;
  return new;
end;
$function$;

alter table public.cameras drop constraint cameras_frame_size_valid;
alter table public.cameras add constraint cameras_frame_size_valid
  check (app_private.camera_frame_ok(format, frame_size));

-- ── Registro de cambios ───────────────────────────────────────────────────

alter table public.catalog_changes drop constraint catalog_changes_entity_check;
alter table public.catalog_changes add constraint catalog_changes_entity_check
  check (entity in ('film_stock', 'manufacturer', 'lab', 'camera_model', 'lens_mount'));

notify pgrst, 'reload schema';
