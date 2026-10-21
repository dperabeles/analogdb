-- ANA-179 production candidate. Preserve current production view and existing rows.
alter table public.rolls add column expiration_year integer;
alter table public.rolls add constraint rolls_expiration_year_valid check (
  expiration_year is null or (fresh is false and expiration_year between 1000 and 9999)
);
comment on column public.rolls.expiration_year is 'Optional expiration year for a film explicitly marked expired when used. No inference from the current date.';
create or replace view public.rolls_flat with (security_invoker = true) as
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
    r.dev_lab_id AS "DEV LAB ID",
    r.scan_lab_id AS "SCAN LAB ID",
    r.camera_id AS "CAMERA ID",
    r.lens_id AS "LENS ID",
    c.supports_interchangeable_lenses AS "CAMERA INTERCHANGEABLE",
    r.expiration_year AS "EXPIRATION YEAR"
   FROM rolls r
     LEFT JOIN film_stocks fs ON fs.id = r.film_stock_id
     LEFT JOIN cameras c ON c.id = r.camera_id
     LEFT JOIN lenses l ON l.id = r.lens_id
     LEFT JOIN labs dl ON dl.id = r.dev_lab_id
     LEFT JOIN labs sl ON sl.id = r.scan_lab_id
     LEFT JOIN LATERAL ( SELECT count(*) FILTER (WHERE re.lens_source IS NOT NULL OR COALESCE(re.luz_natural, false) OR re.apertura IS NOT NULL OR re.shutter_speed IS NOT NULL OR COALESCE(re.tripie, false) OR COALESCE(re.filtros, false) OR COALESCE(re.flash, false) OR COALESCE(re.multiple_exposures, false) OR NULLIF(TRIM(BOTH FROM re.notes), ''::text) IS NOT NULL) AS frame_settings_count
           FROM roll_exposures re
          WHERE re.roll_id = r.id) re_stats ON true;
notify pgrst, 'reload schema';

