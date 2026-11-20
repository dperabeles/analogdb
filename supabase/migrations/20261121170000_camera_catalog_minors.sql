-- Catálogo de cámaras: arreglos menores de la revisión final (20-nov).
--
-- · Una versión vieja de la app manda el cuadro solo en 120: en una cámara de
--   220, 620 o gran formato con varios cuadros, el suyo ya no se pierde.
-- · Una montura que se fusionó después de que la app la guardó lleva a la
--   montura en que se fusionó, en vez de dar «revisa los datos».
-- · admin_manufacturer_merge_preview: antes de fusionar dos marcas, cuánto se
--   mueve y cuántas personas quedarían con dos cámaras iguales.
-- Reescritas desde 20261121090000 y 20261121110000 (iguales en staging y
-- producción el 20-nov).

create function app_private.lens_mount_live(p_id bigint)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id bigint := p_id;
  v_next bigint;
begin
  for i in 1..5 loop
    select merged_into into v_next from public.lens_mounts where id = v_id and status = 'merged';
    exit when v_next is null;
    v_id := v_next;
  end loop;
  return v_id;
end;
$$;
revoke all on function app_private.lens_mount_live(bigint) from public, anon, authenticated;

create or replace function app_private.cameras_follow_model()
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
  -- An id kept from before a merge (an app's cache) means its target.
  select m.* into v_model from public.camera_models m where m.id = new.camera_model_id;
  for i in 1..10 loop
    exit when v_model.id is null or v_model.status <> 'merged';
    select m.* into v_model from public.camera_models m where m.id = v_model.merged_into;
  end loop;
  if v_model.id is null
     or not (v_model.status = 'approved'
             or (v_model.created_by = new.owner_user_id
                 and v_model.status in ('pending', 'rejected'))) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  -- Nor a maker that is someone else's proposal.
  select m.name into v_maker from public.manufacturers m
   where m.id = v_model.manufacturer_id
     and (m.status = 'approved'
          or (m.created_by = new.owner_user_id and m.status in ('pending', 'rejected')));
  if v_maker is null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  new.camera_model_id := v_model.id;
  select name into v_mount from public.lens_mounts where id = v_model.mount_id;

  new.maker := v_maker;
  new.model := v_model.name;
  new.type := v_model.type;
  new.format := v_model.format;
  new.mount := v_mount;
  new.supports_interchangeable_lenses :=
    coalesce(v_model.interchangeable, new.supports_interchangeable_lenses);
  -- An older app sends no frame outside 120: the camera keeps its own.
  if tg_op = 'UPDATE' and new.frame_size is null and old.frame_size = any (v_model.frame_sizes) then
    new.frame_size := old.frame_size;
  end if;
  if cardinality(v_model.frame_sizes) = 0 then
    new.frame_size := null;
  elsif new.frame_size is null or not (new.frame_size = any (v_model.frame_sizes)) then
    new.frame_size := v_model.frame_sizes[1];
  end if;
  return new;
end;
$$;

create or replace function public.propose_camera_model(
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
  -- A mount merged after the app read it means the mount it went into.
  p_mount_id := app_private.lens_mount_live(p_mount_id);
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

create or replace function public.admin_camera_model_update(
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
  -- A mount merged after the app read it means the mount it went into.
  p_mount_id := app_private.lens_mount_live(p_mount_id);
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
                         or (v_model.status in ('pending', 'rejected')
                             and m.status in ('pending', 'rejected')
                             and m.created_by = v_model.created_by)))
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

create function public.admin_manufacturer_merge_preview(p_from bigint, p_into bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_into text;
begin
  perform app_private.require_admin();
  select name into v_into from public.manufacturers where id = p_into;
  return jsonb_build_object(
    'films', (select count(*) from public.film_stocks where manufacturer_id = p_from),
    'camera_models', (select count(*) from public.camera_models where manufacturer_id = p_from),
    'cameras', (select count(*) from public.cameras c join public.camera_models m on m.id = c.camera_model_id
                 where m.manufacturer_id = p_from),
    'collisions', (select count(distinct c.owner_user_id)
                     from public.cameras c join public.camera_models m on m.id = c.camera_model_id
                    where m.manufacturer_id = p_from
                      and exists (select 1 from public.cameras d
                                   where d.owner_user_id = c.owner_user_id and d.id <> c.id
                                     and d.match_key = public.gear_match_key(v_into, m.name))));
end;
$$;
revoke all on function public.admin_manufacturer_merge_preview(bigint, bigint) from public, anon;
grant execute on function public.admin_manufacturer_merge_preview(bigint, bigint) to authenticated;

notify pgrst, 'reload schema';
