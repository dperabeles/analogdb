-- rolls_flat: exponer dev_lab_id y scan_lab_id
--
-- El nombre de un lab NO identifica al lab. "Bengala" son dos sucursales
-- (Monterrey y Guadalajara), y la vista solo traía el nombre — así que la app
-- no podía saber en cuál se reveló un rollo y prefería no enseñar ciudad.
-- Correcto, y a la vez inútil: el dato SÍ estaba en rolls.dev_lab_id, solo que
-- la vista no lo exponía.
--
-- CREATE OR REPLACE y no DROP + CREATE: un DROP perdería los permisos ya
-- otorgados a los roles de la API, y la app se quedaría sin poder leer.
-- REPLACE los conserva y solo admite añadir columnas al final, que es
-- justo lo que se hace.
--
-- `security_invoker = true` va explícito aunque REPLACE lo conserve: `rolls`
-- tiene RLS, y una vista sin invoker correría con permisos del dueño. El fallo
-- sería que cada usuario viera los rollos de todos, en silencio.
create or replace view public.rolls_flat
with (security_invoker = true) as
 SELECT r.id,
    r.code AS "#",
    fs.type AS "FILM TYPE",
    r.format AS "FORMAT",
        CASE
            WHEN r.fresh IS NULL THEN NULL::text
            WHEN r.fresh THEN 'FRESH'::text
            ELSE 'EXPIRED'::text
        END AS "EXP/FRESH",
    fs.name AS "FILM STOCK",
    fs.manufacturer AS "MANUFACTURER",
    fs.iso AS "ISO",
    r.exp_count AS "EXP",
    c.maker AS "MAKER",
    c.model AS "MODEL NAME",
    c.format AS "C. FORMAT",
    c.type AS "C. TYPE",
    c.mount AS "C. MOUNT",
    COALESCE(NULLIF(TRIM(BOTH FROM concat_ws(' '::text, l.maker, l.model)), ''::text), r.lens) AS "LENS",
    l.mount AS "LENS MOUNT",
    array_to_string(r.locations, ', '::text) AS "LOCATIONS",
    array_to_string(r.photo_types, ', '::text) AS "PHOTO TYPE",
    array_to_string(r.tags, ', '::text) AS "TAGS",
    r.iso_pushed AS "ISO @",
    to_char(r.started::timestamp with time zone, 'YYYY-MM-DD'::text) AS "STARTED",
    to_char(r.finished::timestamp with time zone, 'YYYY-MM-DD'::text) AS "FINISHED",
    r.exp_taken AS "# EXP",
    r.push_pull AS "PUSH/PULL",
    dl.name AS "DEV",
    sl.name AS "SCAN",
    r.status AS "STATUS",
    r.rating AS "RATING",
    r.notes AS "NOTES",
    r.updated_at,
    COALESCE(re_stats.frame_settings_count, 0::bigint)::integer AS "FRAME SETTINGS",
    -- Nuevas, al final (lo único que permite REPLACE).
    --
    -- Existen porque el nombre del lab NO identifica al lab: "Bengala" son
    -- dos sucursales, Monterrey y Guadalajara. Sin el id, la app no podía
    -- saber en cuál revelaste y prefería no enseñar ciudad — correcto y
    -- inútil, porque el dato SÍ estaba, solo que en una columna que la vista
    -- no exponía.
    r.dev_lab_id AS "DEV LAB ID",
    r.scan_lab_id AS "SCAN LAB ID"
   FROM rolls r
     LEFT JOIN film_stocks fs ON fs.id = r.film_stock_id
     LEFT JOIN cameras c ON c.id = r.camera_id
     LEFT JOIN lenses l ON l.id = r.lens_id
     LEFT JOIN labs dl ON dl.id = r.dev_lab_id
     LEFT JOIN labs sl ON sl.id = r.scan_lab_id
     LEFT JOIN LATERAL ( SELECT count(*) FILTER (WHERE re.apertura IS NOT NULL OR re.shutter_speed IS NOT NULL OR COALESCE(re.tripie, false) OR COALESCE(re.filtros, false) OR COALESCE(re.flash, false) OR COALESCE(re.multiple_exposures, false) OR NULLIF(TRIM(BOTH FROM re.notes), ''::text) IS NOT NULL) AS frame_settings_count
           FROM roll_exposures re
          WHERE re.roll_id = r.id) re_stats ON true;
