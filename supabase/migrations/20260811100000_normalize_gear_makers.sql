-- Normaliza el casing de las marcas de equipo (ANA-98).
--
-- ── Qué estaba pasando ────────────────────────────────────────────────────
--
-- `src/features/equipment/actions.ts` guardaba la marca de cámara con
-- `.toUpperCase()`, mientras la app móvil la guarda con el casing canónico de
-- su lista de vocabulario ("Pentax"). La MISMA marca vivía como dos valores:
--
--     Pentax  4 filas   ·  PENTAX  53 filas
--     Canon   5 filas   ·  CANON   36 filas
--     Mamiya  2 filas   ·  MAMIYA  16 filas
--     Nikon   —         ·  NIKON    1 fila
--
-- Nadie lo notó nunca porque la app pinta la marca en mayúsculas al mostrarla
-- (`equipment_screen.dart`), así que en pantalla se ven idénticas. Solo se
-- rompía en los agregados: cualquier "cámara más usada" o "marca más popular"
-- cruzando usuarios contaba Pentax y PENTAX por separado.
--
-- Los LENTES están limpios de casualidad: su acción en la web nunca tuvo el
-- `.toUpperCase()`. Se normalizan aquí igual, por simetría y porque nada
-- impedía que alguien escribiera "pentax" en minúsculas.
--
-- La fuente se arregló en el mismo PR (`normalizeMaker` en la web). Sin eso,
-- esta limpieza duraría hasta el siguiente guardado.
--
-- ── Verificado antes de escribir ──────────────────────────────────────────
--
-- Cero colisiones: agrupando por (owner_user_id, marca normalizada, model) no
-- hay ningún par que quede duplicado, así que no hace falta fusionar filas ni
-- repuntar rollos. Es un UPDATE de casing y nada más.
--
-- ── Lo que NO se toca ─────────────────────────────────────────────────────
--
-- El MODELO se deja intacto: ahí el casing tiene significado ("OM-1N",
-- "500 C/M", "35GL").
--
-- Cuatro filas necesitan criterio humano y quedan como están, a propósito —
-- adivinar el equipo de otra persona es peor que dejarlo:
--
--     id 144   Fuji     / Fujica V2    marca coloquial, canónica sería Fujifilm
--     id 212   CANON    / (sin modelo) le falta el modelo
--     id 279   Olympu   / Om-1N        typo de Olympus
--     id 308   (sin marca) / 35GL      le falta la marca
--
-- (id 279 y 212 SÍ cambian de casing aquí — "Olympu" → "Olympu" no cambia,
--  "CANON" → "Canon" sí. El dato que falta o está mal escrito sigue igual.)

begin;

-- Regla única de normalización, para que la base y los clientes no diverjan.
-- Es la misma que aplica `normalizeMaker` en la web: primera letra de cada
-- palabra en mayúscula, el resto en minúscula.
create or replace function public.normalize_gear_maker(p_maker text)
returns text
language sql
immutable
as $$
  select nullif(initcap(lower(btrim(p_maker))), '');
$$;

comment on function public.normalize_gear_maker(text) is
  'Casing canónico de una marca de equipo: PENTAX/pentax → Pentax. Espejo de normalizeMaker() en la webapp.';

update public.cameras
set maker = public.normalize_gear_maker(maker)
where maker is not null
  and maker is distinct from public.normalize_gear_maker(maker);

update public.lenses
set maker = public.normalize_gear_maker(maker)
where maker is not null
  and maker is distinct from public.normalize_gear_maker(maker);

commit;
