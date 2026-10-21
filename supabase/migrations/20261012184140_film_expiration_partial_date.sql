-- Partial printed expiration; legacy year remains a compatibility projection.
create domain public.film_expiration_date as jsonb
constraint film_expiration_date_valid check (
 value is null or case
 when jsonb_typeof(value)='object' and value ? 'year'
   and jsonb_typeof(value->'year')='number'
 then (value->>'year')::numeric between 1000 and 9999
   and trunc((value->>'year')::numeric)=(value->>'year')::numeric
   and (value-'year'-'month')='{}'::jsonb
   and case when not value ? 'month' or value->'month'='null'::jsonb then true
     when jsonb_typeof(value->'month')='number' then
       (value->>'month')::numeric between 1 and 12
       and trunc((value->>'month')::numeric)=(value->>'month')::numeric
     else false end
 else false end
);
alter table public.rolls add column expiration_date public.film_expiration_date;
comment on column public.rolls.expiration_date is 'Printed partial expiration: year with optional month. Independent of condition when used. Never invents a day or missing month.';
-- ALTER TABLE holds the exclusive lock: no writer can bypass the touch trigger.
alter table public.rolls disable trigger rolls_touch;
update public.rolls set expiration_date=jsonb_build_object('year',expiration_year)
where expiration_year is not null;
alter table public.rolls enable trigger rolls_touch;
create function public.sync_roll_expiration_date() returns trigger
language plpgsql security invoker set search_path=pg_catalog,public as $body$
begin
 if TG_OP='INSERT' then
   if NEW.expiration_date is not null then
     NEW.expiration_year:=case when NEW.fresh is false
       then (NEW.expiration_date->>'year')::numeric::integer else null end;
   elsif NEW.expiration_year is not null and NEW.fresh is false then
     NEW.expiration_date:=jsonb_build_object('year',NEW.expiration_year);
   end if;
   return NEW;
 end if;
 if NEW.expiration_date is distinct from OLD.expiration_date then
   NEW.expiration_year:=case when NEW.fresh is false
     then (NEW.expiration_date->>'year')::numeric::integer else null end;
   return NEW;
 end if;
 -- A legacy editor can mark Expired and submit a year in the same PATCH.
 -- Honor that year before projecting; never discard a month it cannot see.
 if NEW.fresh is distinct from OLD.fresh then
   if NEW.fresh is false and NEW.expiration_year is not null
      and NEW.expiration_year is distinct from OLD.expiration_year then
     if OLD.expiration_date->'month' is not null
        and OLD.expiration_date->'month'<>'null'::jsonb then
       if NEW.expiration_year is distinct from
          (OLD.expiration_date->>'year')::numeric::integer then
         raise exception 'Expiration includes a month; update the app to edit its date'
           using errcode='23514';
       end if;
     else
       NEW.expiration_date:=jsonb_build_object('year',NEW.expiration_year);
     end if;
   end if;
   -- Changing to Fresh implicitly clears the legacy year, never the date.
   NEW.expiration_year:=case when NEW.fresh is false
     then (NEW.expiration_date->>'year')::numeric::integer else null end;
   return NEW;
 end if;
 if NEW.expiration_year is distinct from OLD.expiration_year then
   if OLD.expiration_date->'month' is not null
      and OLD.expiration_date->'month'<>'null'::jsonb then
     raise exception 'Expiration includes a month; update the app to edit its date'
       using errcode='23514';
   end if;
   NEW.expiration_date:=case when NEW.expiration_year is null then null
     else jsonb_build_object('year',NEW.expiration_year) end;
 end if;
 return NEW;
end $body$;
revoke all on function public.sync_roll_expiration_date() from public,anon,authenticated;
create trigger rolls_expiration_date before insert or update on public.rolls
for each row execute function public.sync_roll_expiration_date();
create or replace view public.rolls_flat with (security_invoker=true) as
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
    r.expiration_year AS "EXPIRATION YEAR",
    r.expiration_date::jsonb AS "EXPIRATION DATE"
   FROM rolls r
     LEFT JOIN film_stocks fs ON fs.id = r.film_stock_id
     LEFT JOIN cameras c ON c.id = r.camera_id
     LEFT JOIN lenses l ON l.id = r.lens_id
     LEFT JOIN labs dl ON dl.id = r.dev_lab_id
     LEFT JOIN labs sl ON sl.id = r.scan_lab_id
     LEFT JOIN LATERAL ( SELECT count(*) FILTER (WHERE re.lens_source IS NOT NULL OR COALESCE(re.luz_natural, false) OR re.apertura IS NOT NULL OR re.shutter_speed IS NOT NULL OR COALESCE(re.tripie, false) OR COALESCE(re.filtros, false) OR COALESCE(re.flash, false) OR COALESCE(re.multiple_exposures, false) OR NULLIF(TRIM(BOTH FROM re.notes), ''::text) IS NOT NULL) AS frame_settings_count
           FROM roll_exposures re
          WHERE re.roll_id = r.id) re_stats ON true;
notify pgrst,'reload schema';
