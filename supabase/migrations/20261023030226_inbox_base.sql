-- Buzón privado (ANA-185): tablas base.
--
-- Los avisos los escribe solo el servidor: la app los lee y los marca con
-- funciones. Nada de esto se archiva en la papelera, porque no es contenido
-- del usuario. Borrar la cuenta lo borra todo en cascada.

create table public.inbox_accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- La cuenta se activa la primera vez que su app pide el buzón.
  activated_at timestamptz not null default now(),
  -- Día local de la última revisión; null = todavía no se ha evaluado.
  last_evaluated_on date,
  admin_read_at timestamptz
);

create table public.inbox_policy_notices (
  id uuid primary key default gen_random_uuid(),
  title_es text not null,
  title_en text not null,
  summary_es text not null,
  summary_en text not null,
  url text not null check (url like 'https://%'),
  effective_on date not null,
  published_at timestamptz not null default now(),
  published_by uuid references auth.users (id) on delete set null
);
create index inbox_policy_notices_published_by on public.inbox_policy_notices (published_by);

create table public.inbox_notices (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('develop_reminder', 'missing_camera', 'missing_lens',
    'missing_lab', 'camera_lens_question', 'backlog_incomplete', 'policy_change')),
  roll_id bigint references public.rolls (id) on delete cascade,
  camera_id bigint references public.cameras (id) on delete cascade,
  policy_id uuid references public.inbox_policy_notices (id) on delete cascade,
  detected_at timestamptz not null default now(),
  shown_at timestamptz,   -- null mientras corre el margen de 3 días
  rang_at timestamptz,    -- última vez que pasó a "sin leer"
  read_at timestamptz,
  first_opened_at timestamptz,  -- solo política: prueba de que se avisó
  resolved_at timestamptz,
  dismissed_at timestamptz,
  -- Cada tipo tiene un solo sujeto: rollo, cámara, política o ninguno.
  constraint inbox_notices_subject check (case
    when kind = 'camera_lens_question' then roll_id is null and camera_id is not null and policy_id is null
    when kind = 'policy_change' then roll_id is null and camera_id is null and policy_id is not null
    when kind in ('develop_reminder', 'backlog_incomplete') then roll_id is null and camera_id is null and policy_id is null
    else roll_id is not null and camera_id is null and policy_id is null
  end)
);
-- La identidad del aviso: evaluar dos veces, o dos procesos a la vez, nunca
-- crea otro.
create unique index inbox_notices_identity on public.inbox_notices
  (owner_user_id, kind, coalesce(roll_id::text, camera_id::text, policy_id::text, ''));
create index inbox_notices_roll on public.inbox_notices (roll_id) where roll_id is not null;
create index inbox_notices_camera on public.inbox_notices (camera_id) where camera_id is not null;
create index inbox_notices_policy on public.inbox_notices (policy_id) where policy_id is not null;

-- Rollos cuya cámara o lente se borró: el buzón no les pide ese dato.
create table public.inbox_suppressions (
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  roll_id bigint not null references public.rolls (id) on delete cascade,
  field text not null check (field in ('camera', 'lens')),
  created_at timestamptz not null default now(),
  primary key (owner_user_id, roll_id, field)
);
create index inbox_suppressions_roll on public.inbox_suppressions (roll_id);

-- Novedades y marcas "Nuevo" ya vistas. El contenido vive en la app.
create table public.inbox_seen_keys (
  user_id uuid not null references auth.users (id) on delete cascade,
  key text not null check (key ~ '^[a-z0-9._:-]{1,100}$'),
  seen_at timestamptz not null default now(),
  primary key (user_id, key)
);

-- Cuántas veces sonó ya cada rollo en Por revelar, y desde qué fecha.
create table public.inbox_develop_rings (
  roll_id bigint primary key references public.rolls (id) on delete cascade,
  owner_user_id uuid not null references auth.users (id) on delete cascade,
  started_at timestamptz not null,
  rings smallint not null default 0 check (rings between 0 and 2)
);
create index inbox_develop_rings_owner on public.inbox_develop_rings (owner_user_id);

-- Confirmación del usuario sobre el lente. La columna vieja no cambia: la app
-- actual la lee como bool con true por defecto.
alter table public.cameras add column lens_setup_confirmed_at timestamptz;

-- Lectura: lo propio, con perfil aprobado. Sin políticas de escritura.
alter table public.inbox_accounts enable row level security;
alter table public.inbox_policy_notices enable row level security;
alter table public.inbox_notices enable row level security;
alter table public.inbox_suppressions enable row level security;
alter table public.inbox_seen_keys enable row level security;
alter table public.inbox_develop_rings enable row level security;

revoke all on public.inbox_accounts, public.inbox_policy_notices, public.inbox_notices,
  public.inbox_suppressions, public.inbox_seen_keys, public.inbox_develop_rings
  from public, anon, authenticated;
grant select on public.inbox_accounts, public.inbox_policy_notices, public.inbox_notices,
  public.inbox_suppressions, public.inbox_seen_keys, public.inbox_develop_rings
  to authenticated;

create policy inbox_accounts_select_own on public.inbox_accounts for select to authenticated
  using (user_id = (select auth.uid()) and exists (select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'));
create policy inbox_notices_select_own on public.inbox_notices for select to authenticated
  using (owner_user_id = (select auth.uid()) and exists (select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'));
create policy inbox_suppressions_select_own on public.inbox_suppressions for select to authenticated
  using (owner_user_id = (select auth.uid()) and exists (select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'));
create policy inbox_seen_keys_select_own on public.inbox_seen_keys for select to authenticated
  using (user_id = (select auth.uid()) and exists (select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'));
create policy inbox_develop_rings_select_own on public.inbox_develop_rings for select to authenticated
  using (owner_user_id = (select auth.uid()) and exists (select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'));
create policy inbox_policy_notices_select_approved on public.inbox_policy_notices for select to authenticated
  using (exists (select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'));

-- Quién llama: una cuenta con sesión y perfil aprobado.
create function app_private.inbox_caller()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = 'P1201';
  end if;
  if not exists (select 1 from public.profiles p where p.user_id = v_uid and p.status = 'approved') then
    raise exception 'profile_not_approved' using errcode = 'P1202';
  end if;
  return v_uid;
end;
$$;

-- Zona de la cuenta, si es válida; si no, la de México.
create function app_private.inbox_zone(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.timezone from public.profiles p
     where p.user_id = p_uid
       and exists (select 1 from pg_catalog.pg_timezone_names z where z.name = p.timezone)),
    'America/Mexico_City');
$$;

-- Fecha local de un instante para una cuenta. Los días del buzón se cuentan así.
create function app_private.inbox_local_date(p_uid uuid, p_at timestamptz)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (p_at at time zone app_private.inbox_zone(p_uid))::date;
$$;

revoke all on function app_private.inbox_caller(), app_private.inbox_zone(uuid),
  app_private.inbox_local_date(uuid, timestamptz) from public, anon, authenticated;
