-- Catálogo de cámaras, Fase 3 (Diego, 19-nov): monturas, modelos de cámara
-- compartidos y moderados como los films, y la cámara de cada usuario que
-- sigue a su modelo (sin alias).
--
-- · Las cámaras que ya existen no se tocan: ninguna recibe modelo aquí.
-- · Una propuesta pendiente o rechazada la ven solo su autor y el admin,
--   también al apuntar una cámara a ella.
-- · El vocabulario (tipo, formato, cuadro) es una sola lista en el servidor,
--   la misma que escribe la app.
-- · Proponer, corregir, fusionar con vista previa y deshacer, como los films.
--   Una persona tiene una sola cámara por modelo hasta enero: lo que la
--   dejaría con dos iguales falla con P1115 y no cambia nada.

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

-- ── Que las cámaras sigan a sus modelos ───────────────────────────────────

-- Vuelve a copiar el modelo en sus cámaras. Si así una persona quedaría con
-- dos cámaras iguales (una por modelo por persona, hasta enero), no se hace.
create function app_private.camera_models_follow(p_models bigint[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.cameras set camera_model_id = camera_model_id
   where camera_model_id = any (p_models);
exception when unique_violation then
  raise exception 'gear_collision' using errcode = 'P1115';
end;
$$;

create function app_private.manufacturer_cameras_follow(p_maker bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.camera_models_follow(
    array(select id from public.camera_models where manufacturer_id = p_maker));
end;
$$;

create function app_private.camera_model_snapshot(m public.camera_models)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('manufacturer_id', m.manufacturer_id, 'name', m.name,
    'type', m.type, 'format', m.format, 'frame_sizes', to_jsonb(m.frame_sizes),
    'mount_id', m.mount_id, 'interchangeable', m.interchangeable,
    'year_from', m.year_from, 'year_to', m.year_to, 'status', m.status,
    'merged_into', m.merged_into, 'reviewed_by', m.reviewed_by, 'reviewed_at', m.reviewed_at)
$$;

create function app_private.lens_mount_snapshot(m public.lens_mounts)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('name', m.name, 'status', m.status, 'merged_into', m.merged_into)
$$;

-- Los datos de un modelo, los mismos para proponer y para corregir.
create function app_private.camera_model_fields_ok(
  p_name text, p_type text, p_format text, p_frame_sizes text[], p_mount_id bigint,
  p_year_from integer, p_year_to integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_name <> '' and length(p_name) <= 120
     and app_private.camera_type_ok(p_type)
     and app_private.camera_format_ok(p_format)
     and app_private.camera_frames_ok(p_format, p_frame_sizes)
     and (p_mount_id is null
          or exists (select 1 from public.lens_mounts where id = p_mount_id and status = 'approved'))
     and (p_year_from is null or p_year_from between 1839 and 2100)
     and (p_year_to is null or p_year_to between 1839 and 2100)
     and (p_year_from is null or p_year_to is null or p_year_to >= p_year_from)
$$;

-- Cuántas personas quedarían con dos cámaras iguales si las cámaras de
-- [p_from] pasaran a llamarse como [p_into].
create function app_private.camera_model_collisions(p_from bigint, p_into bigint)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(distinct c.owner_user_id)::integer
    from public.cameras c
    join public.camera_models t on t.id = p_into
    join public.manufacturers tm on tm.id = t.manufacturer_id
   where c.camera_model_id = p_from
     and exists (select 1 from public.cameras d
                  where d.owner_user_id = c.owner_user_id and d.id <> c.id
                    and d.match_key = public.gear_match_key(tm.name, t.name))
$$;

-- ── Proponer ──────────────────────────────────────────────────────────────

create function public.propose_camera_model(
  p_manufacturer_id bigint,
  p_name text,
  p_type text default null,
  p_format text default null,
  p_frame_sizes text[] default null,
  p_mount_id bigint default null,
  p_interchangeable boolean default null,
  p_year_from integer default null,
  p_year_to integer default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.require_approved();
  v_maker public.manufacturers;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_key text := app_private.camera_model_key(v_name);
  v_id bigint;
begin
  select * into v_maker from public.manufacturers m
   where m.id = p_manufacturer_id
     and (m.status = 'approved'
          or (m.created_by = v_user and m.status in ('pending', 'rejected')));
  if not found or v_key = ''
     or not app_private.camera_model_fields_ok(v_name, p_type, p_format, p_frame_sizes,
                                                p_mount_id, p_year_from, p_year_to) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('camera_model:' || v_maker.id || ':' || v_key, 0));
  select id into v_id from public.camera_models
   where status = 'approved' and manufacturer_id = v_maker.id
     and app_private.camera_model_key(name) = v_key;
  if found then return v_id; end if;
  select id into v_id from public.camera_models
   where created_by = v_user and status in ('pending', 'rejected') and manufacturer_id = v_maker.id
     and app_private.camera_model_key(name) = v_key;
  if found then return v_id; end if;
  insert into public.camera_models
    (manufacturer_id, name, type, format, frame_sizes, mount_id, interchangeable,
     year_from, year_to, source, status, created_by)
  values (v_maker.id, v_name, p_type, p_format, coalesce(p_frame_sizes, '{}'), p_mount_id,
          p_interchangeable, p_year_from, p_year_to, 'usuario', 'pending', v_user)
  returning id into v_id;
  return v_id;
end;
$$;

-- ── Moderar modelos ───────────────────────────────────────────────────────

-- Corrige un modelo, pendiente o aprobado; sus cámaras lo siguen.
create function public.admin_camera_model_update(
  p_id bigint,
  p_manufacturer_id bigint,
  p_name text,
  p_type text,
  p_format text,
  p_frame_sizes text[],
  p_mount_id bigint,
  p_interchangeable boolean,
  p_year_from integer,
  p_year_to integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_model public.camera_models;
  v_before jsonb;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_change bigint;
begin
  select * into v_model from public.camera_models where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  v_before := app_private.camera_model_snapshot(v_model);
  if v_model.status not in ('pending', 'approved', 'rejected') then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  if not exists (select 1 from public.manufacturers m
                  where m.id = p_manufacturer_id
                    and (m.status = 'approved'
                         or (m.status in ('pending', 'rejected') and m.created_by = v_model.created_by)))
     or app_private.camera_model_key(v_name) = ''
     or not app_private.camera_model_fields_ok(v_name, p_type, p_format, p_frame_sizes,
                                                p_mount_id, p_year_from, p_year_to) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  begin
    update public.camera_models
       set manufacturer_id = p_manufacturer_id, name = v_name, type = p_type, format = p_format,
           frame_sizes = coalesce(p_frame_sizes, '{}'), mount_id = p_mount_id,
           interchangeable = p_interchangeable, year_from = p_year_from, year_to = p_year_to
     where id = p_id
    returning * into v_model;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  perform app_private.camera_models_follow(array[p_id]);
  insert into public.catalog_changes (entity, entity_id, action, before, after, changed_by)
  values ('camera_model', p_id, 'edit', v_before, app_private.camera_model_snapshot(v_model), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

create function public.admin_camera_model_merge_preview(p_from bigint, p_into bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.require_admin();
  return jsonb_build_object(
    'cameras', (select count(*) from public.cameras where camera_model_id = p_from),
    'people', (select count(distinct owner_user_id) from public.cameras where camera_model_id = p_from),
    'collisions', app_private.camera_model_collisions(p_from, p_into));
end;
$$;

-- «Fusionar con…»: las cámaras de [p_from] pasan a [p_into], que debe estar
-- aprobado. Si alguien quedaría con dos iguales, no se hace.
create function public.admin_camera_model_merge(p_from bigint, p_into bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_from public.camera_models;
  v_into public.camera_models;
  v_moved jsonb;
  v_change bigint;
begin
  if p_from is null or p_into is null or p_from = p_into then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_from from public.camera_models where id = p_from for update;
  select * into v_into from public.camera_models where id = p_into for update;
  if v_from.id is null or v_into.id is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_from.status = 'merged' or v_into.status <> 'approved' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  if app_private.camera_model_collisions(p_from, p_into) > 0 then
    raise exception 'gear_collision' using errcode = 'P1115';
  end if;
  v_moved := jsonb_build_object('cameras',
    coalesce((select jsonb_agg(id) from public.cameras where camera_model_id = p_from), '[]'));
  begin
    update public.cameras set camera_model_id = p_into where camera_model_id = p_from;
  exception when unique_violation then
    raise exception 'gear_collision' using errcode = 'P1115';
  end;
  update public.camera_models
     set status = 'merged', merged_into = p_into, reviewed_by = v_admin, reviewed_at = now()
   where id = p_from;
  insert into public.catalog_changes
    (entity, entity_id, action, target_id, before, after, moved, changed_by)
  values ('camera_model', p_from, 'merge', p_into, app_private.camera_model_snapshot(v_from),
          app_private.camera_model_snapshot((select m from public.camera_models m where m.id = p_from)),
          v_moved, v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

-- Deshacer: el modelo vuelve a como estaba, y vuelven solo las cámaras que
-- siguen en el destino.
create function public.admin_camera_model_undo_merge(p_change_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_change public.catalog_changes;
begin
  select * into v_change from public.catalog_changes
   where id = p_change_id and entity = 'camera_model' and action = 'merge'
   for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_change.undone_at is not null then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  -- Primero el modelo: el disparador de cámaras solo acepta uno visible.
  update public.camera_models
     set status = v_change.before ->> 'status',
         merged_into = (v_change.before ->> 'merged_into')::bigint,
         reviewed_by = (v_change.before ->> 'reviewed_by')::uuid,
         reviewed_at = (v_change.before ->> 'reviewed_at')::timestamptz
   where id = v_change.entity_id and status = 'merged' and merged_into = v_change.target_id;
  if not found then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  begin
    update public.cameras set camera_model_id = v_change.entity_id
     where camera_model_id = v_change.target_id
       and id in (select (x)::bigint from jsonb_array_elements_text(v_change.moved -> 'cameras') x);
  exception when unique_violation then
    raise exception 'gear_collision' using errcode = 'P1115';
  end;
  update public.catalog_changes set undone_at = now(), undone_by = v_admin
   where id = p_change_id;
end;
$$;

-- Aprobar o rechazar una propuesta. Aprobar una cuyo nombre ya existe la
-- fusiona con la aprobada. Rechazada, su autor la sigue viendo y usando.
create function public.admin_camera_model_review(p_id bigint, p_decision text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_model public.camera_models;
  v_target bigint;
begin
  if p_decision is null or p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_model from public.camera_models where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_model.status not in ('pending', 'rejected') then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'camera_model:' || v_model.manufacturer_id || ':' || app_private.camera_model_key(v_model.name), 0));
  if p_decision = 'rejected' then
    update public.camera_models
       set status = 'rejected', reviewed_by = v_admin, reviewed_at = now()
     where id = p_id;
    return null;
  end if;
  if not exists (select 1 from public.manufacturers
                  where id = v_model.manufacturer_id and status = 'approved') then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  select id into v_target from public.camera_models
   where status = 'approved' and manufacturer_id = v_model.manufacturer_id
     and app_private.camera_model_key(name) = app_private.camera_model_key(v_model.name);
  if found then
    return public.admin_camera_model_merge(p_id, v_target);
  end if;
  update public.camera_models
     set status = 'approved', reviewed_by = v_admin, reviewed_at = now()
   where id = p_id;
  return null;
end;
$$;

-- ── Moderar monturas ──────────────────────────────────────────────────────

create function public.admin_lens_mount_update(p_id bigint, p_name text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_before public.lens_mounts;
  v_after public.lens_mounts;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_change bigint;
begin
  if v_name = '' or length(v_name) > 60 or app_private.manufacturer_key(v_name) = '' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_before from public.lens_mounts where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_before.status = 'merged' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  begin
    update public.lens_mounts set name = v_name where id = p_id returning * into v_after;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  perform app_private.camera_models_follow(
    array(select id from public.camera_models where mount_id = p_id));
  insert into public.catalog_changes (entity, entity_id, action, before, after, changed_by)
  values ('lens_mount', p_id, 'edit', app_private.lens_mount_snapshot(v_before),
          app_private.lens_mount_snapshot(v_after), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

create function public.admin_lens_mount_merge(p_from bigint, p_into bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_from public.lens_mounts;
  v_into public.lens_mounts;
  v_models bigint[];
  v_change bigint;
begin
  if p_from is null or p_into is null or p_from = p_into then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_from from public.lens_mounts where id = p_from for update;
  select * into v_into from public.lens_mounts where id = p_into for update;
  if v_from.id is null or v_into.id is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_from.status = 'merged' or v_into.status <> 'approved' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  v_models := array(select id from public.camera_models where mount_id = p_from);
  update public.camera_models set mount_id = p_into where mount_id = p_from;
  update public.lens_mounts set status = 'merged', merged_into = p_into where id = p_from;
  perform app_private.camera_models_follow(v_models);
  insert into public.catalog_changes
    (entity, entity_id, action, target_id, before, after, moved, changed_by)
  values ('lens_mount', p_from, 'merge', p_into, app_private.lens_mount_snapshot(v_from),
          app_private.lens_mount_snapshot((select m from public.lens_mounts m where m.id = p_from)),
          jsonb_build_object('models', to_jsonb(v_models)), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

create function public.admin_lens_mount_undo_merge(p_change_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_change public.catalog_changes;
  v_models bigint[];
begin
  select * into v_change from public.catalog_changes
   where id = p_change_id and entity = 'lens_mount' and action = 'merge'
   for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_change.undone_at is not null then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  update public.lens_mounts set status = 'approved', merged_into = null
   where id = v_change.entity_id and status = 'merged' and merged_into = v_change.target_id;
  if not found then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  v_models := array(select (x)::bigint from jsonb_array_elements_text(v_change.moved -> 'models') x);
  update public.camera_models set mount_id = v_change.entity_id
   where mount_id = v_change.target_id and id = any (v_models);
  perform app_private.camera_models_follow(v_models);
  update public.catalog_changes set undone_at = now(), undone_by = v_admin
   where id = p_change_id;
end;
$$;

-- ── Fabricantes: sus cámaras los siguen ───────────────────────────────────
-- Reescritas desde la definición viva (iguales en staging y producción el
-- 19-nov); lo nuevo es lo de cámaras.

create or replace function public.admin_manufacturer_update(p_id bigint, p_name text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_before public.manufacturers;
  v_after public.manufacturers;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_change bigint;
begin
  if v_name = '' or length(v_name) > 80 or app_private.manufacturer_key(v_name) = '' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_before from public.manufacturers where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_before.status = 'merged' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  begin
    update public.manufacturers set name = v_name where id = p_id returning * into v_after;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  perform app_private.manufacturer_films_follow(p_id);
  perform app_private.manufacturer_cameras_follow(p_id);
  insert into public.catalog_changes (entity, entity_id, action, before, after, changed_by)
  values ('manufacturer', p_id, 'edit', app_private.manufacturer_snapshot(v_before),
          app_private.manufacturer_snapshot(v_after), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

create or replace function public.admin_manufacturer_merge(p_from bigint, p_into bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_from public.manufacturers;
  v_into public.manufacturers;
  v_films jsonb;
  v_models jsonb;
  v_change bigint;
begin
  if p_from is null or p_into is null or p_from = p_into then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_from from public.manufacturers where id = p_from for update;
  select * into v_into from public.manufacturers where id = p_into for update;
  if v_from.id is null or v_into.id is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_from.status = 'merged' or v_into.status <> 'approved' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  v_films := coalesce((select jsonb_agg(id) from public.film_stocks where manufacturer_id = p_from), '[]');
  v_models := coalesce((select jsonb_agg(id) from public.camera_models where manufacturer_id = p_from), '[]');
  begin
    update public.film_stocks set manufacturer_id = p_into where manufacturer_id = p_from;
    update public.camera_models set manufacturer_id = p_into where manufacturer_id = p_from;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  perform app_private.manufacturer_cameras_follow(p_into);
  update public.manufacturers
     set status = 'merged', merged_into = p_into, reviewed_by = v_admin, reviewed_at = now()
   where id = p_from;
  insert into public.catalog_changes
    (entity, entity_id, action, target_id, before, after, moved, changed_by)
  values ('manufacturer', p_from, 'merge', p_into, app_private.manufacturer_snapshot(v_from),
          app_private.manufacturer_snapshot((select m from public.manufacturers m where m.id = p_from)),
          jsonb_build_object('films', v_films, 'camera_models', v_models), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

create or replace function public.admin_manufacturer_undo_merge(p_change_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_change public.catalog_changes;
begin
  select * into v_change from public.catalog_changes
   where id = p_change_id and entity = 'manufacturer' and action = 'merge'
   for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_change.undone_at is not null then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  update public.manufacturers
     set status = v_change.before ->> 'status', merged_into = null,
         reviewed_by = (v_change.before ->> 'reviewed_by')::uuid,
         reviewed_at = (v_change.before ->> 'reviewed_at')::timestamptz
   where id = v_change.entity_id and status = 'merged' and merged_into = v_change.target_id;
  if not found then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  begin
    update public.film_stocks set manufacturer_id = v_change.entity_id
     where manufacturer_id = v_change.target_id
       and id in (select (x)::bigint from jsonb_array_elements_text(v_change.moved -> 'films') x);
    update public.camera_models set manufacturer_id = v_change.entity_id
     where manufacturer_id = v_change.target_id
       and id in (select (x)::bigint from jsonb_array_elements_text(
                    coalesce(v_change.moved -> 'camera_models', '[]')) x);
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  perform app_private.manufacturer_cameras_follow(v_change.entity_id);
  update public.catalog_changes set undone_at = now(), undone_by = v_admin
   where id = p_change_id;
end;
$$;

-- ── Los fabricantes que ofrece cada formulario ────────────────────────────

-- El de film nuevo ofrece quien hace films; el de cámara, quien hace
-- cámaras; los dos, los fabricantes propios por revisar.
create function public.catalog_manufacturers(p_kind text)
returns setof public.manufacturers
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_kind is null or p_kind not in ('film', 'camera') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  return query
  select m.* from public.manufacturers m
   where (m.status in ('pending', 'rejected') and m.created_by = (select auth.uid()))
      or (m.status = 'approved' and p_kind = 'film'
          and exists (select 1 from public.film_stocks f
                       where f.manufacturer_id = m.id and f.status = 'approved'))
      or (m.status = 'approved' and p_kind = 'camera'
          and exists (select 1 from public.camera_models c
                       where c.manufacturer_id = m.id and c.status = 'approved'))
   order by m.name;
end;
$$;

-- ── Permisos ──────────────────────────────────────────────────────────────

revoke all on function app_private.camera_models_follow(bigint[]) from public, anon, authenticated;
revoke all on function app_private.manufacturer_cameras_follow(bigint) from public, anon, authenticated;
revoke all on function app_private.camera_model_snapshot(public.camera_models) from public, anon, authenticated;
revoke all on function app_private.lens_mount_snapshot(public.lens_mounts) from public, anon, authenticated;
revoke all on function app_private.camera_model_fields_ok(text, text, text, text[], bigint, integer, integer) from public, anon, authenticated;
revoke all on function app_private.camera_model_collisions(bigint, bigint) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.propose_camera_model(bigint, text, text, text, text[], bigint, boolean, integer, integer)',
    'public.admin_camera_model_update(bigint, bigint, text, text, text, text[], bigint, boolean, integer, integer)',
    'public.admin_camera_model_merge_preview(bigint, bigint)',
    'public.admin_camera_model_merge(bigint, bigint)',
    'public.admin_camera_model_undo_merge(bigint)',
    'public.admin_camera_model_review(bigint, text)',
    'public.admin_lens_mount_update(bigint, text)',
    'public.admin_lens_mount_merge(bigint, bigint)',
    'public.admin_lens_mount_undo_merge(bigint)',
    'public.catalog_manufacturers(text)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
