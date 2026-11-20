-- Catálogo de cámaras: arreglos de la revisión final (19-nov).
--
-- · Una marca que es propuesta de alguien nunca llega a la cámara de otra
--   persona: un modelo aprobado no puede pasar a la marca sin aprobar de su
--   autor, deshacer una fusión de marcas se niega si algo de lo que movió ya
--   se aprobó (también films), y el disparador de cámaras lo vuelve a
--   revisar.
-- · Una cámara que apunta a un modelo ya fusionado (el caché de la app)
--   sigue al modelo en que se fusionó, en vez de dar error al guardar.
-- Reescritas desde 20261121090000, aplicada igual en staging y producción.

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
  if cardinality(v_model.frame_sizes) = 0 then
    new.frame_size := null;
  elsif new.frame_size is null or not (new.frame_size = any (v_model.frame_sizes)) then
    new.frame_size := v_model.frame_sizes[1];
  end if;
  return new;
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
  -- Back to a proposal, while something it carried was approved since: the
  -- proposal's name would reach everyone who uses that film or camera.
  if v_change.before ->> 'status' <> 'approved'
     and (exists (select 1 from public.film_stocks f
                   where f.status = 'approved'
                     and f.id in (select (x)::bigint from jsonb_array_elements_text(v_change.moved -> 'films') x))
          or exists (select 1 from public.camera_models c
                      where c.status = 'approved'
                        and c.id in (select (x)::bigint from jsonb_array_elements_text(
                                       coalesce(v_change.moved -> 'camera_models', '[]')) x))) then
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

notify pgrst, 'reload schema';
