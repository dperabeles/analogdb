-- Salvaguardas contra el borrado accidental.
--
-- ── Por qué existen ─────────────────────────────────────────────────────────
--
-- Diego, 2026-09-17: "lo que me dices que casi borras todo, por favor crea una
-- salvaguarda. Es lo más crucial que tenemos: si borramos algo, la reputación
-- se nos cae."
--
-- No es hipotético. Dos incidentes del mismo día:
--
--   · un borrador roto de `admin_behavior_stats` aplicado a producción,
--     detectado solo porque se verificó justo después;
--   · el capturador de labs borró veinte filas de Diego por un bug propio.
--
-- ── El modelo de amenaza, medido antes de diseñar ──────────────────────────
--
-- Se revisó cada borrado que existe:
--
--     rolls          delete().eq('id', ...)                    UNA fila
--     cameras        delete().eq('id', ...)                    UNA fila
--     lenses         delete().eq('id', ...)                    UNA fila
--     roll_exposures delete().eq('roll_id').eq('frame_number') UNA fila
--     delete_my_account  →  delete from auth.users  →  CASCADA   masivo
--
-- Es decir: **nada legítimo borra más de una fila por sentencia**, salvo el
-- cierre de cuenta — y ese no borra tabla por tabla, borra de `auth.users` y
-- el resto cae por cascada.
--
-- Eso hace que un freno por número de filas sea seguro: no hay caso legítimo
-- que atropelle.
--
-- ── La bandera, y por qué una sola sirve para las dos cosas ────────────────
--
-- El cierre de cuenta es la excepción, y tiene DOS necesidades opuestas al
-- resto:
--
--     bandera puesta   → permite el borrado masivo Y NO archiva
--     bandera ausente  → bloquea el masivo Y archiva
--
-- Que no archive es lo importante y casi se me pasa: **una papelera retendría
-- los datos de alguien que pidió borrar su cuenta**, que es exactamente lo
-- contrario de lo que esa persona pidió. La papelera protege del descuido, no
-- de la voluntad.
--
-- La bandera es una variable de sesión que solo pone `delete_my_account`. Un
-- `delete` a mano en el editor de SQL no la tiene, y por tanto no puede
-- disfrazarse de cierre de cuenta.

-- ── La papelera ─────────────────────────────────────────────────────────────
create table if not exists public.deleted_rows (
  id          bigserial primary key,
  tabla       text        not null,
  fila_id     text        not null,
  dueno       uuid,
  fila        jsonb       not null,
  borrado_por uuid,
  borrado_en  timestamptz not null default now()
);

create index if not exists deleted_rows_tabla_idx  on public.deleted_rows(tabla, borrado_en desc);
create index if not exists deleted_rows_dueno_idx  on public.deleted_rows(dueno);

comment on table public.deleted_rows is
  'Papelera. Cada fila borrada se copia aquí ANTES de irse, salvo las que se '
  'van por cierre de cuenta (esas deben desaparecer de verdad).';

alter table public.deleted_rows enable row level security;

-- Solo admins leen la papelera. Contiene filas de cualquier usuario, así que
-- exponerla a `authenticated` sería una fuga entre usuarios.
drop policy if exists deleted_rows_admin_select on public.deleted_rows;
create policy deleted_rows_admin_select on public.deleted_rows
  for select using (public.app_is_admin(auth.uid()));

-- ── La bandera ──────────────────────────────────────────────────────────────
--
-- `current_setting` con el segundo argumento en true devuelve null si no está
-- puesta, en vez de lanzar. Sin eso, cada borrado normal reventaría.
create or replace function public.borrado_de_cuenta_en_curso()
returns boolean
language sql
stable
as $function$
  select coalesce(current_setting('app.borrando_cuenta', true), '') = 'si';
$function$;

-- ── Archivar antes de borrar ────────────────────────────────────────────────
create or replace function public.archivar_fila_borrada()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_dueno uuid;
  v_fila  jsonb := to_jsonb(old);
begin
  -- El cierre de cuenta NO se archiva: quien pide borrarse tiene derecho a
  -- que no quede copia.
  if public.borrado_de_cuenta_en_curso() then
    return old;
  end if;

  -- El dueño solo si la tabla lo tiene; `labs` es compartida y no lo tiene.
  v_dueno := nullif(v_fila->>'owner_user_id', '')::uuid;

  insert into public.deleted_rows (tabla, fila_id, dueno, fila, borrado_por)
  values (tg_table_name, coalesce(v_fila->>'id', '?'), v_dueno, v_fila, auth.uid());

  return old;
end;
$function$;

-- ── Frenar el borrado masivo ────────────────────────────────────────────────
--
-- A nivel de SENTENCIA, no de fila: así se cuenta el total de una sola vez y
-- se aborta la transacción entera antes de que nada se confirme.
create or replace function public.frenar_borrado_masivo()
returns trigger
language plpgsql
as $function$
declare
  n bigint;
  tope int := 5;
begin
  if public.borrado_de_cuenta_en_curso() then
    return null;
  end if;

  select count(*) into n from borradas;

  if n > tope then
    raise exception
      'FRENO DE SEGURIDAD: se intentaron borrar % filas de "%" en una sola '
      'sentencia (el tope es %). Nada legitimo de la app borra mas de una fila '
      'por sentencia. Si esto es intencional, hazlo por lotes o revisa el '
      'WHERE — que casi siempre es lo que falta.',
      n, tg_table_name, tope;
  end if;
  return null;
end;
$function$;

-- ── Colgarlo de las tablas que duelen ───────────────────────────────────────
--
-- `labs` va con papelera pero SIN freno: la fusión de duplicados no borra
-- nada (deja inactivo), así que un borrado masivo de labs tampoco es
-- legítimo — pero el catálogo es compartido y un tope bajo podría estorbar a
-- una limpieza futura. Se archiva, que es lo que permite deshacer.
do $$
declare t text;
begin
  foreach t in array array['rolls', 'roll_exposures', 'cameras', 'lenses', 'labs']
  loop
    execute format(
      'drop trigger if exists zz_archivar_borrado on public.%I', t);
    execute format(
      'create trigger zz_archivar_borrado before delete on public.%I '
      'for each row execute function public.archivar_fila_borrada()', t);
  end loop;

  foreach t in array array['rolls', 'roll_exposures', 'cameras', 'lenses']
  loop
    execute format(
      'drop trigger if exists zz_frenar_masivo on public.%I', t);
    execute format(
      'create trigger zz_frenar_masivo after delete on public.%I '
      'referencing old table as borradas '
      'for each statement execute function public.frenar_borrado_masivo()', t);
  end loop;
end $$;

-- ── El cierre de cuenta pone la bandera ─────────────────────────────────────
--
-- `set local` la limita a la transacción: al acabar desaparece sola, así que
-- no puede quedarse puesta y desarmar las salvaguardas del resto.
create or replace function public.delete_my_account()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'auth'
as $function$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- Candado del founder: es la única cuenta irreemplazable del proyecto
  -- (is_founder es exclusivo del dueño) y perderla no tiene vuelta atrás.
  -- App Review nunca lo toca: los revisores usan su propia cuenta de prueba.
  if exists (
    select 1 from public.user_roles
    where user_id = uid and is_founder
  ) then
    raise exception 'founder account cannot be self-deleted';
  end if;

  -- Esto es un borrado masivo LEGÍTIMO, y además no debe dejar copia en la
  -- papelera. La bandera dice las dos cosas de una vez.
  perform set_config('app.borrando_cuenta', 'si', true);

  delete from auth.users where id = uid;
end;
$function$;

revoke all on function public.borrado_de_cuenta_en_curso() from public, anon;
