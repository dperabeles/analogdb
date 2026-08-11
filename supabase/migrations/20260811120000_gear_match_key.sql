-- `match_key` en cámaras y lentes: la guarda estructural del equipo (ANA-98).
--
-- ── Por qué en la base y no en los clientes ───────────────────────────────
--
-- La web y la app comparten esta base y los usuarios usan LAS DOS. El
-- fragmentado de marcas que se acaba de limpiar pasó exactamente por eso: la
-- web guardaba `PENTAX` y la app `Pentax`, cada una coherente consigo misma
-- y con la otra no. Cualquier acuerdo que viva solo en el cliente se rompe en
-- cuanto uno de los dos cambie. Por eso la regla baja aquí.
--
-- ── Qué hace ──────────────────────────────────────────────────────────────
--
-- Un trigger BEFORE que, en cada alta y cada edición:
--   1. normaliza el casing de `maker` (PENTAX/pentax → Pentax)
--   2. calcula `match_key`, la identidad del equipo ignorando mayúsculas y
--      espacios de más
--
-- Funciona para TODOS los clientes, incluidos los que ya están instalados en
-- teléfonos y no se van a actualizar hoy. Eso es lo que lo hace seguro.
--
-- ── Qué NO hace, a propósito ──────────────────────────────────────────────
--
-- No se tocan las restricciones únicas existentes
-- (`cameras_owner_maker_model_key`, `lenses_owner_user_id_maker_model_mount_key`).
-- La webapp hace `upsert(..., { onConflict: "owner_user_id,maker,model" })`, y
-- PostgREST necesita que esa única exista con esas columnas exactas. Quitarla
-- rompería el alta de equipo desde la web en el instante en que se aplicara
-- esta migración, antes de poder desplegar nada.
--
-- La única de `match_key` se AÑADE encima. Las dos conviven: la vieja sigue
-- sirviendo al upsert de la web, la nueva atrapa además los duplicados que la
-- vieja no veía (espacios de más). Es aditivo — no hay ventana en la que algo
-- quede roto.
--
-- El MODELO no se normaliza nunca: ahí el casing significa algo ("OM-1N",
-- "500 C/M", "35GL").
--
-- ── Verificado antes de escribir ──────────────────────────────────────────
--
-- Cero colisiones de `match_key` en las 125 cámaras y los 16 lentes, tras la
-- limpieza de 20260811110000. Sin eso, el índice único no se podría crear.
-- Respaldo tomado de las tres tablas implicadas.

begin;

-- ── 1. La identidad del equipo ────────────────────────────────────────────
--
-- Deliberadamente CONSERVADORA: minúsculas, espacios colapsados y recorte.
-- No quita acentos ni puntuación. Una normalización más agresiva atraparía
-- más duplicados pero también fusionaría equipos distintos, y fusionar de
-- más es peor que dejar un duplicado: borra historial de alguien.
create or replace function public.gear_match_key(
  p_maker text,
  p_model text,
  p_mount text default null
)
returns text
language sql
immutable
as $$
  select lower(btrim(regexp_replace(coalesce(p_maker, ''), '\s+', ' ', 'g')))
      || '|'
      || lower(btrim(regexp_replace(coalesce(p_model, ''), '\s+', ' ', 'g')))
      || case
           when p_mount is null then ''
           else '|' || lower(btrim(regexp_replace(p_mount, '\s+', ' ', 'g')))
         end;
$$;

comment on function public.gear_match_key(text, text, text) is
  'Identidad de una pieza de equipo ignorando mayúsculas y espacios de más. Conservadora a propósito: no quita acentos ni puntuación, porque fusionar de más borra historial.';


-- ── 2. Columnas ───────────────────────────────────────────────────────────

alter table public.cameras add column if not exists match_key text;
alter table public.lenses  add column if not exists match_key text;

comment on column public.cameras.match_key is
  'Calculada por trigger. No escribir desde el cliente.';
comment on column public.lenses.match_key is
  'Calculada por trigger (incluye la montura). No escribir desde el cliente.';


-- ── 3. El trigger que lo mantiene ─────────────────────────────────────────
--
-- BEFORE, para que el valor ya esté puesto cuando se evalúen las únicas.
-- Ignora lo que mande el cliente en `match_key`: es un campo derivado.

create or replace function public.gear_normalize_camera()
returns trigger
language plpgsql
as $$
begin
  new.maker := public.normalize_gear_maker(new.maker);
  new.match_key := public.gear_match_key(new.maker, new.model);
  return new;
end;
$$;

create or replace function public.gear_normalize_lens()
returns trigger
language plpgsql
as $$
begin
  new.maker := public.normalize_gear_maker(new.maker);
  new.match_key := public.gear_match_key(new.maker, new.model, new.mount);
  return new;
end;
$$;

drop trigger if exists cameras_gear_normalize on public.cameras;
create trigger cameras_gear_normalize
before insert or update on public.cameras
for each row
execute function public.gear_normalize_camera();

drop trigger if exists lenses_gear_normalize on public.lenses;
create trigger lenses_gear_normalize
before insert or update on public.lenses
for each row
execute function public.gear_normalize_lens();


-- ── 4. Relleno de lo que ya existe ────────────────────────────────────────

update public.cameras
set match_key = public.gear_match_key(maker, model)
where match_key is null;

update public.lenses
set match_key = public.gear_match_key(maker, model, mount)
where match_key is null;

alter table public.cameras alter column match_key set not null;
alter table public.lenses  alter column match_key set not null;


-- ── 5. La guarda ──────────────────────────────────────────────────────────
--
-- Se AÑADE; no sustituye a las únicas existentes (ver cabecera).

create unique index if not exists cameras_owner_match_key_idx
  on public.cameras (owner_user_id, match_key);

create unique index if not exists lenses_owner_match_key_idx
  on public.lenses (owner_user_id, match_key);

commit;
