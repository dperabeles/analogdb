-- admin_behavior_stats: el escalón de equipo, para que el embudo diga la verdad.
--
-- Medido en produccion antes de escribir esto: 21 cuentas, 18 con equipo
-- cargado, 12 con rollos. O sea que de los 9 que "nunca empezaron", SEIS
-- llegaron a montar su camara y se pararon en el formulario de rollo.
--
-- Eso no es "no le intereso": es el producto perdiendolos en un sitio
-- concreto. Sin este escalon, el panel los contaba junto a quien no volvio a
-- abrir la app, que es el diagnostico contrario.
--
-- Cambio aditivo: solo se anade `users_with_gear`.

CREATE OR REPLACE FUNCTION public.admin_behavior_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  resultado jsonb;
begin
  if not public.app_is_admin(auth.uid()) then
    raise exception 'admin only';
  end if;

  with
  -- Un usuario "activo" es uno que registró al menos un rollo en la ventana.
  actividad as (
    select
      count(distinct owner_user_id) filter (where created_at > now() - interval '7 days')  as activos_7d,
      count(distinct owner_user_id) filter (where created_at > now() - interval '30 days') as activos_30d,
      count(*) filter (where created_at > now() - interval '7 days')  as rollos_7d,
      count(*) filter (where created_at > now() - interval '30 days') as rollos_30d
    from public.rolls
  ),
  altas as (
    select
      count(*) filter (where created_at > now() - interval '30 days') as altas_30d,
      count(*) filter (where created_at > now() - interval '7 days')  as altas_7d
    from public.profiles
  ),
  -- Rollos por usuario, solo entre quienes tienen al menos uno.
  por_usuario as (
    select owner_user_id, count(*) as n
    from public.rolls
    group by owner_user_id
  ),
  -- Retención: de los que llevan 30+ días registrados, cuántos siguen vivos.
  -- El denominador excluye a los recién llegados, que aún no tuvieron tiempo
  -- de irse — incluirlos inflaría el número sin decir nada.
  cohorte as (
    select
      count(*) as veteranos,
      count(*) filter (
        where exists (
          select 1 from public.rolls r
          where r.owner_user_id = p.user_id
            and r.created_at > now() - interval '30 days'
        )
      ) as retenidos
    from public.profiles p
    where p.created_at < now() - interval '30 days'
  ),
  -- El número que más dice sobre el onboarding: cuántos se registraron y
  -- nunca llegaron a cargar un rollo.
  -- Aperturas de la app, que NO es lo mismo que rollos cargados.
  --
  -- "Activo" significaba una sola cosa: registró un rollo. Eso confunde dos
  -- situaciones opuestas — abrió y no cargó nada (algo le estorbó) vs. ni
  -- siquiera abrió (se le olvidó). La primera se arregla con producto; la
  -- segunda con un recordatorio.
  aperturas as (
    select
      count(*) filter (where last_mobile_seen_at > now() - interval '7 days')  as abrieron_7d,
      count(*) filter (where last_mobile_seen_at > now() - interval '30 days') as abrieron_30d,
      -- Denominador honesto: quien nunca abrió desde que existe la columna no
      -- es "alguien que dejó de venir", es alguien de quien no sabemos.
      count(last_mobile_seen_at) as han_abierto,
      count(distinct timezone) as zonas
    from public.profiles
    where status = 'approved'
  ),
  -- El escalón que faltaba en el embudo: quién llegó a cargar EQUIPO.
  --
  -- "Se registró → cargó un rollo" mete en el mismo saco a quien no volvió a
  -- abrir la app y a quien se montó su cámara y se atascó en el formulario de
  -- rollo. Son diagnósticos opuestos: el primero es un problema de recordar,
  -- el segundo es un problema del producto, y solo el segundo se arregla
  -- tocando código.
  con_equipo as (
    select count(*) as n
    from public.profiles p
    where exists (select 1 from public.cameras c where c.owner_user_id = p.user_id)
       or exists (select 1 from public.lenses l where l.owner_user_id = p.user_id)
  ),
  sin_estrenar as (
    select count(*) as n
    from public.profiles p
    where not exists (select 1 from public.rolls r where r.owner_user_id = p.user_id)
  ),
  profundidad as (
    select
      count(*) as total_rollos,
      count(*) filter (
        where exists (select 1 from public.roll_exposures e where e.roll_id = r.id)
      ) as con_fotogramas,
      count(*) filter (where r.dev_lab_id is not null) as con_lab
    from public.rolls r
  ),
  -- Serie de las últimas 12 semanas. Se generan TODAS las semanas y se hace
  -- left join: sin eso, una semana sin rollos desaparecería y la gráfica
  -- mentiría uniendo dos puntos lejanos como si fueran contiguos.
  semanas as (
    select generate_series(
      date_trunc('week', now() - interval '11 weeks'),
      date_trunc('week', now()),
      interval '1 week'
    ) as semana
  ),
  serie as (
    select s.semana, count(r.id) as n
    from semanas s
    left join public.rolls r
      on date_trunc('week', r.created_at) = s.semana
    group by s.semana
    order by s.semana
  )
  select jsonb_build_object(
    'active_7d',        (select activos_7d from actividad),
    'active_30d',       (select activos_30d from actividad),
    'rolls_7d',         (select rollos_7d from actividad),
    'rolls_30d',        (select rollos_30d from actividad),
    'signups_7d',       (select altas_7d from altas),
    'signups_30d',      (select altas_30d from altas),
    'users_total',      (select count(*) from public.profiles),
    'users_with_rolls', (select count(*) from por_usuario),
    'never_started',    (select n from sin_estrenar),
    'users_with_gear',  (select n from con_equipo),
    'cohort_30d',       (select veteranos from cohorte),
    'retained_30d',     (select retenidos from cohorte),
    'median_rolls',     coalesce(
                          (select percentile_cont(0.5) within group (order by n)
                           from por_usuario), 0),
    'max_rolls',        coalesce((select max(n) from por_usuario), 0),
    'rolls_with_frames',(select con_fotogramas from profundidad),
    'rolls_with_lab',   (select con_lab from profundidad),
    'rolls_total',      (select total_rollos from profundidad),
    'opened_7d',        (select abrieron_7d from aperturas),
    'opened_30d',       (select abrieron_30d from aperturas),
    'ever_opened',      (select han_abierto from aperturas),
    'timezones',        (select zonas from aperturas),
    'weekly',           (select coalesce(jsonb_agg(
                            jsonb_build_object('week', to_char(semana, 'YYYY-MM-DD'), 'rolls', n)
                            order by semana), '[]'::jsonb) from serie)
  )
  into resultado;

  return resultado;
end;
$function$
;
