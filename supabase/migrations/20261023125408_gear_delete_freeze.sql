-- Equipo borrado: el rollo conserva el nombre de su cámara y de su lente.
--
-- ── Por qué ─────────────────────────────────────────────────────────────────
--
-- `rolls.camera_id` y `rolls.lens_id` son `on delete set null`, y `rolls_flat`
-- saca maker, modelo, formato y montura solo del join. Borrar una cámara le
-- quitaba a sus rollos la cámara y el nombre, en silencio y sin vuelta atrás:
-- la papelera guarda la cámara, no qué rollos la usaban, y restaurarla le da
-- otro id. En producción la cámara más usada de Diego tiene 47 rollos. Los
-- fotogramas ya conservaban el nombre (`roll_exposures.lens_snapshot`).
--
-- Contrato aprobado por Diego el 22-oct-2026 (opción A). Mismo patrón que
-- `costs_freeze_equipment`: congelar al borrar, no al capturar.
--
-- ── Qué hace ────────────────────────────────────────────────────────────────
--
-- 1. `rolls.camera_snapshot` y `rolls.lens_snapshot`: copia de la pieza en el
--    momento de borrarla, v1 como el snapshot de fotogramas. Null mientras la
--    pieza exista.
-- 2. `app_private.rolls_freeze_gear()`, `before delete` en cameras y lenses:
--    escribe el snapshot en los rollos del mismo dueño. NO vacía la llave (lo
--    sigue haciendo el `set null`): así todos los `before delete` (costos, el
--    buzón, este) ven los rollos todavía enlazados, en cualquier orden. Solo
--    escribe: nunca impide borrar.
-- 3. `app_private.rolls_guard_gear_snapshot()`, `before insert or update` en
--    rolls: un cliente no escribe snapshots; elegir otra pieza, o escribir otro
--    texto de lente, deja atrás el snapshot.
-- 4. `rolls_flat`: si la pieza ya no existe, las mismas columnas muestran el
--    snapshot; al final se agregan "CAMERA DELETED" y "LENS DELETED". La app
--    instalada y la web lo ven sin actualizarse.
--
-- Medido en staging antes de escribirlo: un update emitido desde un disparador
-- `security definer` y el `set null` de la llave corren como `postgres`; un
-- cliente de PostgREST, como `authenticated` o `anon`. Por eso la guarda mira
-- el rol y no `pg_trigger_depth()` (que ya engañó una vez: el freno de borrado).

-- ── 1. Columnas ─────────────────────────────────────────────────────────────

alter table public.rolls
  add column camera_snapshot jsonb,
  add column lens_snapshot jsonb;

-- `is true`: un CHECK que da null pasa, y un `->` sobre una llave que falta da
-- null. Sin esto, un snapshot sin `version` entraría.
alter table public.rolls add constraint rolls_camera_snapshot_v1 check ((
  camera_snapshot is null
  or (jsonb_typeof(camera_snapshot) = 'object'
      and camera_snapshot -> 'version' = '1'::jsonb
      and jsonb_typeof(camera_snapshot -> 'display_name') = 'string'
      and length(btrim(camera_snapshot ->> 'display_name')) > 0)
) is true);

alter table public.rolls add constraint rolls_lens_snapshot_v1 check ((
  lens_snapshot is null
  or (jsonb_typeof(lens_snapshot) = 'object'
      and lens_snapshot -> 'version' = '1'::jsonb
      and jsonb_typeof(lens_snapshot -> 'display_name') = 'string'
      and length(btrim(lens_snapshot ->> 'display_name')) > 0)
) is true);

comment on column public.rolls.camera_snapshot is
  'La camara tal como era al borrarla (v1: display_name, maker, model, format, '
  'type, mount, interchangeable, camera_id original, frozen_at). Null mientras '
  'exista. Solo la escribe el servidor; elegir otra camara la borra.';
comment on column public.rolls.lens_snapshot is
  'El lente tal como era al borrarlo (v1, como roll_exposures.lens_snapshot, '
  'mas lens_id original y frozen_at). Null mientras exista. Solo la escribe el '
  'servidor; elegir otro lente o escribir otro texto de lente la borra.';

-- ── 2. Congelar al borrar ───────────────────────────────────────────────────

create function app_private.rolls_freeze_gear()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- El mismo texto que arma rolls_flat, para que el rollo se vea igual.
  v_name text := nullif(btrim(concat_ws(' ', old.maker, old.model)), '');
begin
  -- El cierre de cuenta se lleva los rollos en la misma cascada. Y una pieza
  -- sin marca ni modelo no tiene nombre que conservar.
  if public.borrado_de_cuenta_en_curso() or v_name is null then
    return old;
  end if;

  -- Solo rollos del mismo dueño: nunca copiar el nombre de un equipo ajeno.
  if tg_table_name = 'cameras' then
    update public.rolls
       set camera_snapshot = jsonb_build_object(
             'version', 1,
             'display_name', v_name,
             'maker', old.maker,
             'model', old.model,
             'format', old.format,
             'type', old.type,
             'mount', old.mount,
             'interchangeable', old.supports_interchangeable_lenses,
             'camera_id', old.id,
             'frozen_at', now())
     where camera_id = old.id and owner_user_id = old.owner_user_id;
  else
    update public.rolls
       set lens_snapshot = jsonb_build_object(
             'version', 1,
             'display_name', v_name,
             'maker', old.maker,
             'model', old.model,
             'mount', old.mount,
             'is_zoom', old.is_zoom,
             'focal_min', old.focal_min,
             'focal_max', old.focal_max,
             'max_aperture', old.max_aperture,
             'max_aperture_tele', old.max_aperture_tele,
             'lens_id', old.id,
             'frozen_at', now())
     where lens_id = old.id and owner_user_id = old.owner_user_id;
  end if;
  return old;
end;
$$;
revoke all on function app_private.rolls_freeze_gear() from public, anon, authenticated;

create trigger gear_freeze_rolls before delete on public.cameras
for each row execute function app_private.rolls_freeze_gear();
create trigger gear_freeze_rolls before delete on public.lenses
for each row execute function app_private.rolls_freeze_gear();

-- ── 3. Guarda en rolls ──────────────────────────────────────────────────────

-- SECURITY INVOKER a propósito: `current_user` tiene que ser quien escribe.
create function app_private.rolls_guard_gear_snapshot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Un cliente no inventa ni borra un snapshot. El congelado y la llave corren
  -- como el dueño de las tablas, no como authenticated.
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.camera_snapshot := null;
      new.lens_snapshot := null;
    else
      new.camera_snapshot := old.camera_snapshot;
      new.lens_snapshot := old.lens_snapshot;
    end if;
  end if;

  if tg_op = 'UPDATE' then
    -- Elegir otra pieza deja atrás la borrada. Guardar el rollo con la llave
    -- vacía (lo que manda la app para un rollo así) no cambia nada.
    if new.camera_id is not null and new.camera_id is distinct from old.camera_id then
      new.camera_snapshot := null;
    end if;
    if new.lens_id is not null and new.lens_id is distinct from old.lens_id then
      new.lens_snapshot := null;
    end if;
    -- La web escribe el lente como texto. Si el usuario escribió otro, el
    -- snapshot no debe taparlo en rolls_flat.
    if new.lens is distinct from old.lens then
      new.lens_snapshot := null;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function app_private.rolls_guard_gear_snapshot() from public, anon, authenticated;

create trigger rolls_gear_snapshot_guard before insert or update on public.rolls
for each row execute function app_private.rolls_guard_gear_snapshot();

-- ── 4. rolls_flat ───────────────────────────────────────────────────────────
--
-- Reemplazos puntuales sobre la definición viva, como en 20260926190000: así
-- se conserva todo lo demás tal como esté en cada base (staging y producción
-- difieren en "FRAME SETTINGS"). Cada pieza tiene que aparecer exactamente una
-- vez, o la migración se detiene. La pieza viva siempre gana, aunque tenga un
-- campo vacío: el snapshot solo se lee cuando el join no encontró nada.

do $migration$
declare
  v_def text := pg_get_viewdef('public.rolls_flat'::regclass, true);
  v_pair text[];
  v_count int;
  v_pairs text[] := array[
    [$a$c.maker AS "MAKER"$a$,
     $b$CASE WHEN c.id IS NULL THEN r.camera_snapshot ->> 'maker' ELSE c.maker END AS "MAKER"$b$],
    [$a$c.model AS "MODEL NAME"$a$,
     $b$CASE WHEN c.id IS NULL THEN r.camera_snapshot ->> 'model' ELSE c.model END AS "MODEL NAME"$b$],
    [$a$c.format AS "C. FORMAT"$a$,
     $b$CASE WHEN c.id IS NULL THEN r.camera_snapshot ->> 'format' ELSE c.format END AS "C. FORMAT"$b$],
    [$a$c.type AS "C. TYPE"$a$,
     $b$CASE WHEN c.id IS NULL THEN r.camera_snapshot ->> 'type' ELSE c.type END AS "C. TYPE"$b$],
    [$a$c.mount AS "C. MOUNT"$a$,
     $b$CASE WHEN c.id IS NULL THEN r.camera_snapshot ->> 'mount' ELSE c.mount END AS "C. MOUNT"$b$],
    [$a$COALESCE(NULLIF(TRIM(BOTH FROM concat_ws(' '::text, l.maker, l.model)), ''::text), r.lens) AS "LENS"$a$,
     $b$COALESCE(NULLIF(TRIM(BOTH FROM concat_ws(' '::text, l.maker, l.model)), ''::text), CASE WHEN l.id IS NULL THEN r.lens_snapshot ->> 'display_name' END, r.lens) AS "LENS"$b$],
    [$a$l.mount AS "LENS MOUNT"$a$,
     $b$CASE WHEN l.id IS NULL THEN r.lens_snapshot ->> 'mount' ELSE l.mount END AS "LENS MOUNT"$b$],
    [$a$c.supports_interchangeable_lenses AS "CAMERA INTERCHANGEABLE"$a$,
     $b$CASE WHEN c.id IS NULL THEN (r.camera_snapshot ->> 'interchangeable')::boolean ELSE c.supports_interchangeable_lenses END AS "CAMERA INTERCHANGEABLE"$b$],
    [$a$r.expiration_date::jsonb AS "EXPIRATION DATE"$a$,
     $b$r.expiration_date::jsonb AS "EXPIRATION DATE",
    r.camera_id IS NULL AND r.camera_snapshot IS NOT NULL AS "CAMERA DELETED",
    r.lens_id IS NULL AND r.lens_snapshot IS NOT NULL AS "LENS DELETED"$b$]
  ];
begin
  foreach v_pair slice 1 in array v_pairs loop
    v_count := (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]);
    if v_count <> 1 then
      raise exception 'rolls_flat inesperada: "%" aparece % veces', v_pair[1], v_count;
    end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;

  execute 'create or replace view public.rolls_flat with (security_invoker = true) as ' || v_def;
end
$migration$;

notify pgrst, 'reload schema';
