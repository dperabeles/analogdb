-- Limpieza de cuatro filas de equipo que el casing no arreglaba (ANA-98).
--
-- Requisito PREVIO de la migración de `match_key`: dos de estas filas
-- colisionan al normalizarse, y sin resolverlas la restricción única no se
-- puede crear.
--
-- Decisiones tomadas por Diego el 2026-08-11, una por una. Se anotan aquí
-- porque son datos de OTROS usuarios y el criterio no es reconstruible desde
-- el código.
--
-- ── id 144 · 'Fuji' → 'Fujifilm' ──────────────────────────────────────────
-- Marca coloquial. La canónica del vocabulario de la app es 'Fujifilm'.
-- No colisiona con nada. Sus dos rollos (R003, R004) no se tocan.
--
-- ── id 212 · se queda como está ───────────────────────────────────────────
-- Cámara Canon sin modelo. No hay ningún dato para deducir cuál es, y
-- Diego decidió no inventarlo. Queda con `model` nulo a propósito.
--
-- ── id 308 · se BORRA ─────────────────────────────────────────────────────
-- Es una Minox 35 GL guardada dos veces por el mismo usuario: primero sin
-- marca (308, 0 rollos) y luego bien (309, 1 rollo). Ids consecutivos, mismo
-- modelo, mismo tipo, mismo formato. No es una cámara sin marca: es el
-- intento fallido que quedó huérfano. Rellenarle la marca la convertiría en
-- un duplicado real.
--
-- ── id 279 · se FUSIONA con la 280 ────────────────────────────────────────
-- Mismo patrón, pero con consecuencias: el usuario escribió 'Olympu' (279),
-- corrigió a 'Olympus' (280), y acabó usando LAS DOS — un rollo cada una.
-- Arreglar el typo sin más las habría hecho colisionar.
-- Se repunta el rollo de la 279 a la 280 y se borra la 279. Así el usuario
-- conserva SUS DOS ROLLOS y le queda una sola Olympus OM-1N, que es la
-- cámara que de verdad tiene.
--
-- Respaldo tomado antes de aplicar: cameras (127), lenses (16) y los 5
-- rollos implicados.

begin;

-- 144 — marca coloquial a canónica.
update public.cameras set maker = 'Fujifilm' where id = 144 and maker = 'Fuji';

-- 279 → 280 — primero el historial, después la fila.
-- El orden importa: borrar antes dejaría el rollo apuntando a la nada (o lo
-- arrastraría, según la FK).
update public.rolls
set camera_id = 280
where camera_id = 279;

delete from public.cameras where id = 279;

-- 308 — duplicado huérfano, sin rollos que dependan de él.
delete from public.cameras
where id = 308
  and not exists (select 1 from public.rolls r where r.camera_id = 308);

commit;
