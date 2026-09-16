-- admin_global_stats: añade los top 5 CON CANTIDADES.
--
-- Diego: "solo dame la métrica con número de lo de stock, cámara y formato.
-- Me gustaría ver un top 5 de Stock, con las cantidades."
--
-- Los tres escalares (`top_stock`, `top_camera`, `top_format`) se CONSERVAN:
-- la webapp también lee este RPC y no se toca lo que ya funciona. Se añaden
-- tres arrays nuevos. Cambio puramente aditivo.
--
-- `create or replace` preserva los grants; misma firma (cero argumentos), así
-- que no hay riesgo de sobrecarga ambigua en PostgREST.
create or replace function public.admin_global_stats()
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare result jsonb;
begin
  if not public.app_is_admin(auth.uid()) then raise exception 'admin only'; end if;
  select jsonb_build_object(
    'total_rolls',      (select count(*) from rolls),
    'total_users',      (select count(*) from profiles),
    'total_exposures',  (select count(*) from roll_exposures),
    'rolls_this_month', (select count(*) from rolls where started >= date_trunc('month', now())::date),
    'active_users',     (select count(distinct owner_user_id) from rolls),
    'new_users_this_month', (select count(*) from profiles where created_at >= date_trunc('month', now())),

    -- ── Escalares heredados (los lee la webapp) ────────────────────────────
    'top_stock',  (select trim(fs.manufacturer||' '||fs.name) from rolls r join film_stocks fs on fs.id=r.film_stock_id group by fs.manufacturer, fs.name order by count(*) desc limit 1),
    'top_camera', (select trim(coalesce(c.maker,'')||' '||coalesce(c.model,'')) from rolls r join cameras c on c.id=r.camera_id group by c.maker, c.model order by count(*) desc limit 1),
    'top_format', (select r.format from rolls r where r.format is not null group by r.format order by count(*) desc limit 1),

    -- ── Top 5 con cantidades ───────────────────────────────────────────────
    --
    -- El desempate por nombre no es cosmético: sin él, dos stocks con el mismo
    -- número salen en orden arbitrario y la lista baila entre recargas.
    'top_stocks', (
      select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'rolls', t.n) order by t.n desc, t.name), '[]'::jsonb)
      from (
        select trim(fs.manufacturer||' '||fs.name) as name, count(*) as n
        from rolls r join film_stocks fs on fs.id = r.film_stock_id
        group by fs.manufacturer, fs.name
        order by count(*) desc, trim(fs.manufacturer||' '||fs.name)
        limit 5
      ) t
    ),
    'top_cameras', (
      select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'rolls', t.n) order by t.n desc, t.name), '[]'::jsonb)
      from (
        select trim(coalesce(c.maker,'')||' '||coalesce(c.model,'')) as name, count(*) as n
        from rolls r join cameras c on c.id = r.camera_id
        group by c.maker, c.model
        order by count(*) desc, trim(coalesce(c.maker,'')||' '||coalesce(c.model,''))
        limit 5
      ) t
    ),
    'top_formats', (
      select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'rolls', t.n) order by t.n desc, t.name), '[]'::jsonb)
      from (
        select r.format as name, count(*) as n
        from rolls r
        where r.format is not null
        group by r.format
        order by count(*) desc, r.format
        limit 5
      ) t
    )
  ) into result;
  return result;
end; $function$;
