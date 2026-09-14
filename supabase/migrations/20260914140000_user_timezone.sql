-- profiles.timezone — la zona horaria del usuario, para avisarle a SU hora
--
-- Diego lo pidió al revisar ANA-75 (recordatorio de rollos olvidados): "no
-- quisiera que alguien usando la app en Berlín le llegara la notificación a
-- las 3am". Un push a esa hora no es un recordatorio, es una razón para
-- desinstalar.
--
-- ── Por qué se captura ANTES de que exista el push ───────────────────────
--
-- Porque este dato tiene que ACUMULARSE. Si se agregara el día que se prende
-- el push, ese día no sabríamos la zona de nadie — y el primer envío, que es
-- el que llega a los 200 del grupo de Monterrey, saldría a ciegas.
--
-- ── Por qué el NOMBRE y no el desfase ────────────────────────────────────
--
-- 'Europe/Berlin', no '+02:00'. Con el desfase, en cada cambio de horario de
-- verano toda la base recibiría el aviso una hora corrida, dos veces al año,
-- y nadie entendería por qué. Con el nombre, `AT TIME ZONE` lo resuelve solo.
alter table public.profiles
  add column if not exists timezone text;

comment on column public.profiles.timezone is
  'Zona IANA reportada por la app en cada apertura (ej. America/Monterrey). '
  'NUNCA un desfase: el horario de verano lo rompería dos veces al año.';

-- touch_mobile_seen gana un parámetro. Se reporta en la MISMA llamada que ya
-- se hace al abrir la app: cero viajes de red extra. Y como va en cada
-- apertura, si el usuario viaja o se muda, se corrige solo.
create or replace function public.touch_mobile_seen(
  p_version text default null,
  p_timezone text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tz text;
begin
  if auth.uid() is null then
    return;
  end if;

  -- Se valida contra el catálogo de Postgres antes de guardarla. Un cliente
  -- puede mandar cualquier texto, y una zona inventada haría fallar el
  -- `AT TIME ZONE` del cron MESES después, lejísimos de aquí.
  if nullif(btrim(p_timezone), '') is not null
     and exists (select 1 from pg_timezone_names where name = btrim(p_timezone))
  then
    v_tz := btrim(p_timezone);
  end if;

  update public.profiles
     set last_mobile_seen_at = now(),
         last_mobile_version = coalesce(nullif(btrim(p_version), ''), last_mobile_version),
         -- Igual que la versión: solo se pisa si viene algo válido, para que
         -- una llamada sin argumento no borre lo que ya había.
         timezone = coalesce(v_tz, timezone)
   where user_id = auth.uid();
end $$;

revoke all on function public.touch_mobile_seen(text, text) from public, anon;
grant execute on function public.touch_mobile_seen(text, text) to authenticated;

-- La firma de un argumento se queda huérfana: PostgREST elegiría mal entre
-- dos funciones del mismo nombre ("Could not choose the best candidate").
drop function if exists public.touch_mobile_seen(text);
