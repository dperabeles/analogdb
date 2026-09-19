-- El freno de borrado masivo contaba las cascadas.
--
-- ── El fallo ────────────────────────────────────────────────────────────────
--
-- `frenar_borrado_masivo()` aborta cualquier sentencia que borre más de 5
-- filas. Se instaló con este razonamiento, que se comprobó mirando cada
-- llamada de la app:
--
--     "nada legítimo borra más de una fila por sentencia"
--
-- Cierto de las llamadas de la app. **Falso de la base**, porque
-- `roll_exposures.roll_id → rolls on delete cascade`: la app borra UN rollo y
-- Postgres borra sus N exposiciones. El trigger de sentencia sobre
-- `roll_exposures` ve esas N y aborta.
--
-- Resultado en producción: **un usuario no podía borrar su propio rollo si
-- tenía más de 5 exposiciones.** Hoy son 3 rollos de 16, pero la app soporta
-- hasta 36 fotogramas.
--
-- El ensayo de la vez anterior probó "el freno aborta sin borrar a medias" con
-- borrados directos de varias filas. Nunca con una cascada. Ahí estuvo el
-- hueco: la aserción que faltaba, no el razonamiento.
--
-- ── Lo que NO funciona ──────────────────────────────────────────────────────
--
-- `pg_trigger_depth()` no distingue los dos casos: se midió y devuelve 1 tanto
-- en el borrado directo como en la cascada. Se descartó por medición, no por
-- intuición.
--
-- ── Lo que sí ───────────────────────────────────────────────────────────────
--
-- Mirar si el rollo padre sigue existiendo:
--
--     borrado directo de exposiciones  →  el rollo sigue vivo   → frenar
--     cascada al borrar el rollo       →  el rollo ya no está   → dejar pasar
--
-- Y no es un truco: si el padre también se fue, este borrado es **consecuencia
-- de otro que ya pasó su propio freno** (el de `rolls`, con el mismo tope). La
-- protección contra un `delete from roll_exposures` sin WHERE se conserva
-- entera: ahí los padres siguen vivos.
--
-- Solo cambia `roll_exposures`. `rolls`, `cameras` y `lenses` no tienen ningún
-- padre que les caiga en cascada dentro de la app — el único es `auth.users`, y
-- ése va por la bandera de cierre de cuenta. Se quedan con la función genérica
-- sin tocar.

create or replace function public.frenar_borrado_masivo_exposiciones()
returns trigger
language plpgsql
-- SECURITY DEFINER a propósito: la decisión del freno no debe depender de lo
-- que el usuario que llama alcance a VER. Sin esto, una política de RLS que
-- escondiera el rollo padre haría que el freno lo tomara por borrado, y dejaría
-- pasar un borrado directo. Es un trigger (devuelve `trigger`), así que
-- PostgREST no lo expone como RPC.
security definer
set search_path to 'public'
as $function$
declare
  n            bigint;
  padres_vivos bigint;
  tope         int := 5;
begin
  -- El cierre de cuenta es el único borrado masivo legítimo.
  if public.borrado_de_cuenta_en_curso() then
    return null;
  end if;

  select count(*) into n from borradas;

  -- Por debajo del tope no hace falta averiguar nada más.
  if n <= tope then
    return null;
  end if;

  select count(*) into padres_vivos
    from public.rolls r
   where r.id in (select distinct roll_id from borradas);

  -- Ningún padre vivo = esto lo arrastró el borrado de los rollos, que ya pasó
  -- su propio freno. Las filas SÍ quedan archivadas en la papelera: eso lo hace
  -- el trigger `zz_archivar_borrado`, que es por fila y BEFORE, y la cascada
  -- también lo dispara.
  if padres_vivos = 0 then
    return null;
  end if;

  raise exception
    'FRENO DE SEGURIDAD: se intentaron borrar % exposiciones en una sola '
    'sentencia (el tope es %) y sus rollos siguen existiendo, asi que no es '
    'una cascada. Revisa el WHERE — que casi siempre es lo que falta.',
    n, tope;
end;
$function$;

-- El trigger de `roll_exposures` pasa a la función nueva. Los otros tres no se
-- tocan.
drop trigger if exists zz_frenar_masivo on public.roll_exposures;
create trigger zz_frenar_masivo after delete on public.roll_exposures
  referencing old table as borradas
  for each statement execute function public.frenar_borrado_masivo_exposiciones();

-- Igual que su hermana: no se ofrece a los clientes como función suelta.
revoke all on function public.frenar_borrado_masivo_exposiciones() from public, anon;
