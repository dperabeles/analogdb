-- ANA-104 (ajuste) · lab_usage_stats: ADMIN-ONLY
-- Aplicada a producción el 2026-07-12. Decisión de producto de Diego tras
-- el QA: los agregados globales de labs no deben ser visibles para todos —
-- con base de usuarios chica casi identifican actividad individual.
-- Guard idéntico a admin_global_stats; verificado en vivo (raise 'admin
-- only' para llamadas sin admin).

create or replace function public.lab_usage_stats()
returns table (
  match_key text,
  name text,
  city text,
  country text,
  country_code text,
  rolls bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.app_is_admin(auth.uid()) then
    raise exception 'admin only';
  end if;
  return query
  select l.match_key,
         min(l.name),
         l.city,
         min(l.country),
         l.country_code,
         count(distinct r.id)::bigint
  from public.rolls r
  join public.labs l on l.id in (r.dev_lab_id, r.scan_lab_id)
  group by l.match_key, l.city, l.country_code;
end;
$$;
