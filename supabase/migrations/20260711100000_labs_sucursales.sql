-- ANA-103 · Labs con sucursales (mismo lab, varias ciudades)
-- Aplicada a producción el 2026-07-11 vía supabase db query --linked,
-- en DOS momentos coordinados con los clientes (ver secuencia abajo).
--
-- Secuencia sin ventana de ruptura:
--   A) unique nuevo ADITIVO (coexiste con labs_name_key) ✓
--   B) deploy de clientes: móvil onConflict (match_key,city)
--      [analogdb-mobile#21] + web resolver por match_key [analogdb#11]
--   C) drop del unique viejo + desdoble de Bengala (este archivo, parte 2)
--
-- NULLS NOT DISTINCT (PG15+; producción es PG17): los labs sin ciudad
-- también dedupean. Índices de expresión NO sirven aquí: PostgREST no los
-- acepta como target de on_conflict.

-- A) (aplicada primero, con validación previa de cero duplicados)
alter table public.labs
  add constraint labs_match_city_key unique nulls not distinct (match_key, city);

-- C) (aplicada tras el deploy de ambos clientes)
alter table public.labs drop constraint labs_name_key;

-- Desdoble de Bengala: la fila original (id 1) queda como Monterrey;
-- se crea la sucursal Guadalajara con los datos de marca compartidos.
insert into public.labs (name, city, country, country_code, instagram, active, self_processed)
values ('Bengala', 'Guadalajara', 'México', 'MX', 'bengala____mx', true, false);
