-- Métricas de comportamiento para el panel de admin.
--
-- `admin_global_stats` (ANA-104) responde "cuánto hay": rollos, fotogramas,
-- la película más usada. Esto responde otra cosa: **cómo se comporta la
-- gente** — si vuelven, cada cuánto, y si el producto se está usando o solo
-- se probó una vez.
--
-- ── Privacidad ────────────────────────────────────────────────────────────
--
-- ADMIN-ONLY, forzado en el servidor, por la misma razón que ANA-104: con 21
-- usuarios, un agregado pequeño casi identifica a una persona. Todo lo que
-- devuelve son totales y tendencias — **ninguna consulta baja al nivel de
-- quién hizo qué**, que es exactamente lo que Diego pidió no tener.
--
-- ── Por qué la actividad se mide por rollos y no por sesiones ─────────────
--
-- `profiles.last_mobile_seen_at` existe pero está en NULL para los 21
-- usuarios: nadie la escribe. Medir con ella daría cero siempre.
--
-- Se usa "creó un rollo" como señal de actividad. Es más estrecha —alguien
-- puede abrir la app a consultar sin registrar nada— pero es la única real.
-- Si algún día se cablea `last_mobile_seen_at`, esta función es el sitio
-- donde cambiar la definición.

begin;

create or replace function public.admin_behavior_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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
    'cohort_30d',       (select veteranos from cohorte),
    'retained_30d',     (select retenidos from cohorte),
    'median_rolls',     coalesce(
                          (select percentile_cont(0.5) within group (order by n)
                           from por_usuario), 0),
    'max_rolls',        coalesce((select max(n) from por_usuario), 0),
    'rolls_with_frames',(select con_fotogramas from profundidad),
    'rolls_with_lab',   (select con_lab from profundidad),
    'rolls_total',      (select total_rollos from profundidad),
    'weekly',           (select coalesce(jsonb_agg(
                            jsonb_build_object('week', to_char(semana, 'YYYY-MM-DD'), 'rolls', n)
                            order by semana), '[]'::jsonb) from serie)
  )
  into resultado;

  return resultado;
end;
$$;

comment on function public.admin_behavior_stats() is
  'Métricas de comportamiento agregadas para el panel de admin. Solo totales y tendencias: nunca baja al nivel de usuario individual.';

revoke all on function public.admin_behavior_stats() from public;
revoke all on function public.admin_behavior_stats() from anon;
grant execute on function public.admin_behavior_stats() to authenticated;

commit;
