-- ANA-104 · Métricas globales de labs cross-user
-- Aplicada a producción el 2026-07-11 vía supabase db query --linked.
--
-- rolls tiene RLS por dueño → la agregación global requiere security
-- definer (mismo patrón que admin_global_stats). Devuelve una fila por
-- (marca, ciudad) = sucursal; el cliente agrega totales por marca, top
-- por ciudad y por país. "Uso" = rollos DISTINTOS que tocaron el lab
-- (dev y/o scan en el mismo lab cuenta 1, no 2).
-- Solo usuarios autenticados; anon queda fuera.

create or replace function public.lab_usage_stats()
returns table (
  match_key text,
  name text,
  city text,
  country text,
  country_code text,
  rolls bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select l.match_key,
         min(l.name) as name,
         l.city,
         min(l.country) as country,
         l.country_code,
         count(distinct r.id)::bigint as rolls
  from public.rolls r
  join public.labs l on l.id in (r.dev_lab_id, r.scan_lab_id)
  group by l.match_key, l.city, l.country_code
$$;

revoke all on function public.lab_usage_stats() from public;
revoke all on function public.lab_usage_stats() from anon;
grant execute on function public.lab_usage_stats() to authenticated;
