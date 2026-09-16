-- admin_global_stats: rankings con cantidades Y usuarios distintos.
--
-- Diego: "Stock, Cámaras y Formato pudieran ser su sección cada una, para
-- después poder darle click y sacar ya más datos sobre todos los stocks".
--
-- Dos cambios sobre la versión anterior:
--
--   · **`users` por entrada.** Es la diferencia entre una moda y una manía:
--     "Kodak Gold, 21 rollos, 9 usuarios" y "Kodak Gold, 21 rollos, 1 usuario"
--     son hechos opuestos, y el conteo de rollos solo no los distingue.
--   · **25 entradas en vez de 5.** El panel sigue enseñando 5; las otras 20
--     son para la pantalla de detalle, y caben de sobra en la misma respuesta.
--
--   · **`rolls_by_status`** — dónde se atascan los rollos. "7 por revelar" es
--     exactamente a quien apunta el recordatorio de ANA-75: si ese número
--     crece y nunca baja, el recordatorio no está funcionando.
--
-- Sigue siendo aditivo: los tres escalares que lee la webapp no se tocan.

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

    -- ── Rankings con cantidades Y usuarios distintos ───────────────────────
    --
    -- El desempate por nombre no es cosmético: sin él, dos stocks con el mismo
    -- número salen en orden arbitrario y la lista baila entre recargas.
    'top_stocks', (
      select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'rolls', t.n, 'users', t.u) order by t.n desc, t.name), '[]'::jsonb)
      from (
        select trim(fs.manufacturer||' '||fs.name) as name, count(*) as n, count(distinct r.owner_user_id) as u
        from rolls r join film_stocks fs on fs.id = r.film_stock_id
        
        group by trim(fs.manufacturer||' '||fs.name)
        order by count(*) desc, trim(fs.manufacturer||' '||fs.name)
        limit 25
      ) t
    ),
    'top_cameras', (
      select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'rolls', t.n, 'users', t.u) order by t.n desc, t.name), '[]'::jsonb)
      from (
        select trim(coalesce(c.maker,'')||' '||coalesce(c.model,'')) as name, count(*) as n, count(distinct r.owner_user_id) as u
        from rolls r join cameras c on c.id = r.camera_id
        
        group by trim(coalesce(c.maker,'')||' '||coalesce(c.model,''))
        order by count(*) desc, trim(coalesce(c.maker,'')||' '||coalesce(c.model,''))
        limit 25
      ) t
    ),
    'top_formats', (
      select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'rolls', t.n, 'users', t.u) order by t.n desc, t.name), '[]'::jsonb)
      from (
        select r.format as name, count(*) as n, count(distinct r.owner_user_id) as u
        from rolls r 
        where r.format is not null
        group by r.format
        order by count(*) desc, r.format
        limit 25
      ) t
    ),
    'rolls_by_status', (
      select coalesce(jsonb_agg(jsonb_build_object('name', t.status, 'rolls', t.n) order by t.n desc), '[]'::jsonb)
      from (select r.status, count(*) as n from rolls r where r.status is not null group by r.status) t
    )
  ) into result;
  return result;
end; $function$;
