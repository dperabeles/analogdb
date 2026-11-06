-- Film inventory takes the other roll formats: Super 8 (8), 16 mm (16) and
-- large format (45), stored as rolls.format already stores them. A camera
-- of those formats takes their film.

alter table public.film_units
  drop constraint film_units_format_check,
  add constraint film_units_format_check
    check (format = any (array[35, 120, 110, 8, 16, 45]));

alter table public.film_purchases
  drop constraint film_purchases_inventory_line,
  add constraint film_purchases_inventory_line
    check (origin = 'roll'
           or (film_stock_id is not null
               and format = any (array[35, 120, 110, 8, 16, 45])));

create or replace function app_private.check_film_line(p_film_stock_id bigint, p_format integer)
 returns void
 language plpgsql
 stable
 set search_path to ''
as $function$
begin
  if p_format is null or p_format not in (35, 120, 110, 8, 16, 45)
     or not exists (select 1 from public.film_stocks s where s.id = p_film_stock_id) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
end;
$function$;

create or replace function app_private.camera_roll_format(p_format text)
 returns integer
 language sql
 immutable
 set search_path to ''
as $function$
  select case lower(btrim(p_format))
    when '35' then 35 when '35mm' then 35 when '135' then 35
    when '120' then 120 when '6x4.5' then 120 when 'medium format' then 120 when 'mf' then 120
    when '110' then 110
    when '8' then 8 when 'super8' then 8 when 'super 8' then 8
    when '16' then 16 when '16mm' then 16 when '16 mm' then 16
    when '45' then 45 when 'large format' then 45 when 'lf' then 45 when 'gran formato' then 45
  end
$function$;
