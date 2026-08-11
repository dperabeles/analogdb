-- ═══════════════════════════════════════════════════════════════
-- analogdb — Supabase schema bootstrap (multi-user)
-- Ejecutar sobre un proyecto nuevo de Supabase.
-- Replica el modelo actual de la app: auth por correo, approval manual,
-- founder/admin workflow, rolls privados por usuario y métricas públicas agregadas.
-- ═══════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;
create extension if not exists pg_net;

drop view if exists public.rolls_flat cascade;

drop function if exists public.landing_metrics() cascade;
drop function if exists public.notify_pending_signup() cascade;
drop function if exists public.notify_profile_approved() cascade;
drop function if exists public.handle_new_auth_user() cascade;
drop function if exists public.cast_admin_action_vote(uuid, text) cascade;
drop function if exists public.cancel_admin_action(uuid, text) cascade;
drop function if exists public.request_admin_action(text, uuid, text) cascade;
drop function if exists public.notify_admin_action() cascade;
drop function if exists public.admin_set_profile_status(uuid, text) cascade;
drop function if exists public.app_is_founder(uuid) cascade;
drop function if exists public.app_is_admin(uuid) cascade;
drop function if exists public.gear_normalize_camera() cascade;
drop function if exists public.gear_normalize_lens() cascade;
drop function if exists public.gear_match_key(text, text, text) cascade;
drop function if exists public.normalize_gear_maker(text) cascade;
drop function if exists public.touch_updated_at() cascade;

drop table if exists public.admin_action_approvals cascade;
drop table if exists public.admin_actions cascade;
drop table if exists public.private_app_config cascade;
drop table if exists public.roll_exposures cascade;
drop table if exists public.frame_tags cascade;
drop table if exists public.rolls cascade;
drop table if exists public.cameras cascade;
drop table if exists public.labs cascade;
drop table if exists public.film_stocks cascade;
drop table if exists public.user_roles cascade;
drop table if exists public.profiles cascade;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  -- Default 'approved' desde 20260526: el registro ya no pasa por aprobación
  -- manual (el trigger handle_new_auth_user inserta approved + approved_at).
  status text not null default 'approved' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  rejected_at timestamptz,
  rejected_by uuid references auth.users(id) on delete set null,
  -- Soporte móvil (20260526). Andamiaje para notificaciones push: aún no se
  -- envía nada, pero las columnas existen en producción y la app ya escribe
  -- rolls.marked_to_develop_at.
  fcm_token text,
  fcm_platform text check (fcm_platform in ('ios','android')),
  fcm_token_updated_at timestamptz,
  last_mobile_version text,
  last_mobile_seen_at timestamptz,
  last_terms_accepted_version text,
  last_terms_accepted_at timestamptz,
  notification_prefs jsonb default '{"account_status": true, "roll_reminders": true, "legal_updates": true}'::jsonb,
  check (char_length(btrim(display_name)) >= 3 and char_length(btrim(display_name)) <= 20),
  check (display_name = btrim(display_name))
);

create table public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'admin')),
  is_founder boolean not null default false,
  created_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null
);

create table public.private_app_config (
  config_key text primary key,
  config_value text not null,
  updated_at timestamptz not null default now()
);

create table public.film_stocks (
  id bigint generated always as identity primary key,
  manufacturer text not null,
  name text not null,
  iso integer,
  type text check (type in ('COLOR', 'B/W', 'SLIDE')),
  in_catalog boolean default true,
  unique (manufacturer, name)
);

create table public.labs (
  id bigint generated always as identity primary key,
  name text not null unique
);

create table public.cameras (
  id bigint generated always as identity primary key,
  maker text,
  model text,
  format text,
  type text,
  mount text,
  supports_interchangeable_lenses boolean not null default true,
  show_in_quick_mode boolean not null default true,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  -- Derivada por trigger: identidad ignorando mayúsculas y espacios de más.
  match_key text not null,
  unique (owner_user_id, maker, model)
);

create table public.lenses (
  id bigint generated always as identity primary key,
  maker text not null,
  model text not null,
  mount text,
  show_in_quick_mode boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  -- Derivada por trigger: identidad ignorando mayúsculas y espacios de más.
  match_key text not null,
  unique (owner_user_id, maker, model, mount)
);

create table public.rolls (
  id bigint generated always as identity primary key,
  code text not null,
  film_stock_id bigint references public.film_stocks(id) on delete set null,
  iso_pushed integer,
  format integer,
  exp_count integer,
  exp_taken integer,
  fresh boolean,
  push_pull text,
  camera_id bigint references public.cameras(id) on delete set null,
  lens_id bigint references public.lenses(id) on delete set null,
  lens text,
  locations text[] default '{}'::text[],
  photo_types text[] default '{}'::text[],
  tags text[] default '{}'::text[],
  started date,
  finished date,
  status text,
  dev_lab_id bigint references public.labs(id) on delete set null,
  scan_lab_id bigint references public.labs(id) on delete set null,
  rating integer check (rating >= 0 and rating <= 5),
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  -- Recordatorios de revelado (20260526). La app móvil escribe
  -- marked_to_develop_at al pasar el film a "Por revelar".
  marked_to_develop_at timestamptz,
  last_reminder_sent_at timestamptz,
  constraint rolls_owner_code_unique unique (owner_user_id, code)
);

-- Log de notificaciones push enviadas (20260526). Acceso restringido al
-- rol de servicio (ver el grant en la migración);
-- todavía no se envía nada, existe para cuando se active el envío.
create table public.push_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(user_id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  deeplink text,
  status text not null check (status in ('sent', 'failed', 'opted_out')),
  fcm_response_code int,
  created_at timestamptz default now()
);

create index push_log_user_id_created_at_idx
  on public.push_log (user_id, created_at desc);

create table public.frame_tags (
  id uuid primary key default gen_random_uuid(),
  roll_id text not null,
  frame_start integer not null,
  frame_end integer not null,
  tag text not null,
  created_at timestamptz default now()
);

create table public.roll_exposures (
  id uuid primary key default gen_random_uuid(),
  roll_id bigint not null references public.rolls(id) on delete cascade,
  frame_number integer not null check (frame_number > 0),
  apertura text,
  shutter_speed text,
  tripie boolean,
  filtros boolean,
  flash boolean,
  luz_natural boolean,
  multiple_exposures boolean,
  notes text,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (roll_id, frame_number)
);

create table public.admin_actions (
  id uuid primary key default gen_random_uuid(),
  action_type text not null check (action_type in ('promote_to_admin', 'demote_from_admin')),
  target_user_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('pending', 'approved', 'rejected', 'executed', 'cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_reason text,
  -- Por qué se propuso (lo escribe quien propone; resolved_reason lo escribe
  -- el sistema al resolver). Caducidad tras la cual ya no se puede votar.
  request_reason text,
  expires_at timestamptz
);

create table public.admin_action_approvals (
  action_id uuid not null references public.admin_actions(id) on delete cascade,
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  decision text not null check (decision in ('approved', 'rejected')),
  decided_at timestamptz not null default now(),
  primary key (action_id, admin_user_id)
);

create index rolls_status_idx on public.rolls(status);
create index rolls_started_idx on public.rolls(started);
create index rolls_film_stock_id_idx on public.rolls(film_stock_id);
create index rolls_camera_id_idx on public.rolls(camera_id);
create index rolls_lens_id_idx on public.rolls(lens_id);
create index rolls_owner_user_id_idx on public.rolls(owner_user_id);
create index cameras_owner_user_id_idx on public.cameras(owner_user_id);
create index lenses_owner_user_id_idx on public.lenses(owner_user_id);
create index lenses_owner_mount_idx on public.lenses(owner_user_id, mount);
create index idx_frame_tags_roll_id on public.frame_tags(roll_id);
create index idx_frame_tags_tag on public.frame_tags(tag);
create index roll_exposures_roll_id_idx on public.roll_exposures(roll_id);
create index roll_exposures_roll_frame_idx on public.roll_exposures(roll_id, frame_number);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger rolls_touch
before update on public.rolls
for each row
execute function public.touch_updated_at();

create trigger roll_exposures_touch
before update on public.roll_exposures
for each row
execute function public.touch_updated_at();

create trigger lenses_touch
before update on public.lenses
for each row
execute function public.touch_updated_at();

create or replace function public.notify_pending_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
begin
  -- 20260807: sin filtro por status. Antes había un early return por
  -- 'pending' que dejó el aviso mudo cuando los perfiles pasaron a nacer
  -- 'approved' (20260526).
  begin
    select pac.config_value
    into webhook_secret
    from public.private_app_config pac
    where pac.config_key = 'pending_signup_webhook_secret'
    limit 1;

    if webhook_secret is null or webhook_secret = '' then
      raise notice 'pending signup notification skipped: missing vault secret';
      return new;
    end if;

    perform net.http_post(
      url := 'https://dqjjxxqruxxfsfoejdzl.supabase.co/functions/v1/notify-pending-signup',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'type', tg_op,
        'schema', tg_table_schema,
        'table', tg_table_name,
        'record', to_jsonb(new)
      )
    );
  exception
    when others then
      raise notice 'pending signup notification skipped: %', sqlerrm;
  end;

  return new;
end;
$$;

-- 20260807: sin WHEN — avisa de CUALQUIER registro nuevo. El nombre
-- conserva "pending" porque la Edge Function desplegada vive en esa URL.
create trigger profiles_notify_pending_signup
after insert on public.profiles
for each row
execute function public.notify_pending_signup();

create or replace function public.notify_profile_approved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
begin
  if new.status is distinct from 'approved'
    or old.status is not distinct from 'approved' then
    return new;
  end if;

  begin
    select pac.config_value
    into webhook_secret
    from public.private_app_config pac
    where pac.config_key = 'pending_signup_webhook_secret'
    limit 1;

    if webhook_secret is null or webhook_secret = '' then
      raise notice 'profile approval notification skipped: missing webhook secret';
      return new;
    end if;

    perform net.http_post(
      url := 'https://dqjjxxqruxxfsfoejdzl.supabase.co/functions/v1/notify-profile-approved',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'type', tg_op,
        'schema', tg_table_schema,
        'table', tg_table_name,
        'old_record', to_jsonb(old),
        'record', to_jsonb(new)
      )
    );
  exception
    when others then
      raise notice 'profile approval notification skipped: %', sqlerrm;
  end;

  return new;
end;
$$;

create trigger profiles_notify_approved
after update of status on public.profiles
for each row
when (new.status = 'approved' and old.status is distinct from 'approved')
execute function public.notify_profile_approved();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  requested_display_name text;
begin
  requested_display_name := btrim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  if char_length(requested_display_name) < 3 then
    requested_display_name := btrim(split_part(coalesce(new.email, 'user'), '@', 1));
  end if;

  if char_length(requested_display_name) < 3 then
    requested_display_name := 'User';
  end if;

  requested_display_name := left(requested_display_name, 20);

  insert into public.profiles (
    user_id,
    email,
    display_name,
    status,
    approved_at,
    approved_by,
    rejected_at,
    rejected_by
  )
  values (
    new.id,
    new.email,
    requested_display_name,
    -- 20260526: sin aprobación manual, el registro entra directo.
    'approved',
    now(),
    null,  -- approved_by: nadie lo aprobó, fue automático
    null,
    null
  )
  on conflict (user_id) do nothing;

  insert into public.user_roles (
    user_id,
    role,
    is_founder,
    granted_by
  )
  values (
    new.id,
    'user',
    false,
    null
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created_create_profile
after insert on auth.users
for each row
execute function public.handle_new_auth_user();

create or replace function public.app_is_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.user_roles ur
    where ur.user_id = p_user_id
      and ur.role = 'admin'
  );
$$;

create or replace function public.app_is_founder(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.user_roles ur
    where ur.user_id = p_user_id
      and ur.is_founder = true
  );
$$;

create or replace function public.admin_set_profile_status(p_target_user_id uuid, p_status text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  updated_profile public.profiles;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  if p_status not in ('pending', 'approved', 'rejected') then
    raise exception 'invalid status';
  end if;

  update public.profiles
  set
    status = p_status,
    approved_at = case when p_status = 'approved' then now() else null end,
    approved_by = case when p_status = 'approved' then actor_id else null end,
    rejected_at = case when p_status = 'rejected' then now() else null end,
    rejected_by = case when p_status = 'rejected' then actor_id else null end
  where user_id = p_target_user_id
  returning * into updated_profile;

  if not found then
    raise exception 'profile not found';
  end if;

  return updated_profile;
end;
$$;

create or replace function public.request_admin_action(
  p_action_type text,
  p_target_user_id uuid,
  p_reason text default null
)
returns public.admin_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  created_action public.admin_actions;
  existing_action public.admin_actions;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  if p_action_type not in ('promote_to_admin', 'demote_from_admin') then
    raise exception 'invalid action type';
  end if;

  if p_target_user_id = actor_id then
    raise exception 'self role changes are not allowed';
  end if;

  if p_action_type = 'demote_from_admin' and public.app_is_founder(p_target_user_id) then
    raise exception 'founder admin cannot be demoted';
  end if;

  -- Idempotente: si ya hay una propuesta viva para el mismo usuario y tipo,
  -- se devuelve esa en vez de crear una segunda (cancelar una y dejar viva a
  -- su gemela era incoherente).
  select *
  into existing_action
  from public.admin_actions
  where action_type = p_action_type
    and target_user_id = p_target_user_id
    and status = 'pending'
    and (expires_at is null or now() <= expires_at)
  order by created_at desc
  limit 1;

  if found then
    return existing_action;
  end if;

  insert into public.admin_actions (
    action_type, target_user_id, created_by, status, request_reason, expires_at
  )
  values (
    p_action_type,
    p_target_user_id,
    actor_id,
    'pending',
    nullif(btrim(coalesce(p_reason, '')), ''),
    now() + interval '30 days'
  )
  returning * into created_action;

  return created_action;
end;
$$;

create or replace function public.cast_admin_action_vote(p_action_id uuid, p_decision text)
returns public.admin_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  action_row public.admin_actions;
  target_is_founder boolean;
  eligible_admin_count integer;
  approved_vote_count integer;
  has_rejection boolean;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid decision';
  end if;

  select *
  into action_row
  from public.admin_actions
  where id = p_action_id;

  if not found then
    raise exception 'admin action not found';
  end if;

  if action_row.status <> 'pending' then
    return action_row;
  end if;

  -- Caducidad: una propuesta vencida no se vota, se auto-cancela. Null-safe
  -- para filas anteriores a la migración de endurecimiento.
  if action_row.expires_at is not null and now() > action_row.expires_at then
    update public.admin_actions
    set
      status = 'cancelled',
      resolved_at = now(),
      resolved_reason = 'Expired without unanimous approval'
    where id = p_action_id
    returning * into action_row;
    return action_row;
  end if;

  if action_row.target_user_id = actor_id then
    raise exception 'target user cannot vote on own role change';
  end if;

  target_is_founder := public.app_is_founder(action_row.target_user_id);
  if action_row.action_type = 'demote_from_admin' and target_is_founder then
    update public.admin_actions
    set
      status = 'rejected',
      resolved_at = now(),
      resolved_reason = 'Founder admin cannot be demoted'
    where id = p_action_id
    returning * into action_row;
    return action_row;
  end if;

  insert into public.admin_action_approvals (action_id, admin_user_id, decision)
  values (p_action_id, actor_id, p_decision)
  on conflict (action_id, admin_user_id)
  do update set decision = excluded.decision, decided_at = now();

  select exists(
    select 1
    from public.admin_action_approvals aaa
    where aaa.action_id = p_action_id
      and aaa.decision = 'rejected'
  ) into has_rejection;

  if has_rejection then
    update public.admin_actions
    set
      status = 'rejected',
      resolved_at = now(),
      resolved_reason = 'Rejected by admin vote'
    where id = p_action_id
    returning * into action_row;
    return action_row;
  end if;

  select count(*)
  into eligible_admin_count
  from public.user_roles ur
  where ur.role = 'admin'
    and ur.user_id <> action_row.target_user_id;

  select count(*)
  into approved_vote_count
  from public.admin_action_approvals aaa
  where aaa.action_id = p_action_id
    and aaa.decision = 'approved';

  if approved_vote_count < eligible_admin_count then
    return action_row;
  end if;

  if action_row.action_type = 'promote_to_admin' then
    insert into public.user_roles (user_id, role, is_founder, granted_by)
    values (action_row.target_user_id, 'admin', false, actor_id)
    on conflict (user_id)
    do update set role = 'admin', granted_by = actor_id;
  elsif action_row.action_type = 'demote_from_admin' then
    update public.user_roles
    set role = 'user', granted_by = actor_id
    where user_id = action_row.target_user_id
      and is_founder = false;
  end if;

  update public.admin_actions
  set
    status = 'executed',
    resolved_at = now(),
    resolved_reason = 'Unanimous approval reached'
  where id = p_action_id
  returning * into action_row;

  return action_row;
end;
$$;

create or replace function public.cancel_admin_action(
  p_action_id uuid,
  p_reason text default null
)
returns public.admin_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  action_row public.admin_actions;
  actor_is_requester boolean;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  select *
  into action_row
  from public.admin_actions
  where id = p_action_id;

  if not found then
    raise exception 'admin action not found';
  end if;

  -- Idempotente: si ya se resolvió (ejecutada, rechazada o cancelada), se
  -- devuelve tal cual. Cancelar dos veces no es un error.
  if action_row.status <> 'pending' then
    return action_row;
  end if;

  actor_is_requester := action_row.created_by = actor_id;

  if not actor_is_requester and not public.app_is_founder(actor_id) then
    raise exception 'only the requester or the founder can cancel';
  end if;

  update public.admin_actions
  set
    status = 'cancelled',
    resolved_at = now(),
    resolved_reason = coalesce(
      nullif(btrim(coalesce(p_reason, '')), ''),
      case when actor_is_requester
        then 'Cancelled by requester'
        else 'Cancelled by founder'
      end
    )
  where id = p_action_id
  returning * into action_row;

  return action_row;
end;
$$;

create or replace function public.notify_admin_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
  event_name text;
  target_email text;
  target_name text;
  actor_email text;
  actor_name text;
begin
  if tg_op = 'INSERT' then
    event_name := 'requested';
  elsif new.status = 'executed' and old.status is distinct from 'executed' then
    event_name := 'executed';
  else
    return new;
  end if;

  begin
    select pac.config_value
    into webhook_secret
    from public.private_app_config pac
    where pac.config_key = 'pending_signup_webhook_secret'
    limit 1;

    if webhook_secret is null or webhook_secret = '' then
      raise notice 'admin action notification skipped: missing webhook secret';
      return new;
    end if;

    -- Un correo con dos UUID no le sirve a nadie. La resolución de nombres se
    -- hace aquí, que es donde hay permiso (security definer), y no en la Edge
    -- Function — que necesitaría una credencial elevada propia para lograr lo
    -- mismo. Menos secretos circulando.
    select p.email, p.display_name into target_email, target_name
    from public.profiles p where p.user_id = new.target_user_id;

    select p.email, p.display_name into actor_email, actor_name
    from public.profiles p where p.user_id = new.created_by;

    perform net.http_post(
      url := 'https://dqjjxxqruxxfsfoejdzl.supabase.co/functions/v1/notify-admin-action',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'event', event_name,
        'record', to_jsonb(new),
        'target', jsonb_build_object('email', target_email, 'display_name', target_name),
        'actor', jsonb_build_object('email', actor_email, 'display_name', actor_name)
      )
    );
  exception
    -- El aviso NUNCA debe tumbar un cambio de rol: si falla, se anota y sigue.
    -- Misma lección que el aviso de registros nuevos.
    when others then
      raise notice 'admin action notification skipped: %', sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists admin_actions_notify on public.admin_actions;
create trigger admin_actions_notify
after insert or update of status on public.admin_actions
for each row
execute function public.notify_admin_action();

-- Casing canónico de una marca de equipo: PENTAX/pentax → Pentax.
--
-- Existe porque la web guardaba la marca de cámara en MAYÚSCULAS y la app
-- móvil con el casing de su lista canónica: la misma marca vivía como dos
-- valores y los agregados cruzados entre usuarios los contaban por separado.
-- Espejo de normalizeMaker() en src/features/equipment/actions.ts.
create or replace function public.normalize_gear_maker(p_maker text)
returns text
language sql
immutable
as $$
  select nullif(initcap(lower(btrim(p_maker))), '');
$$;

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

create unique index if not exists cameras_owner_match_key_idx
  on public.cameras (owner_user_id, match_key);

create unique index if not exists lenses_owner_match_key_idx
  on public.lenses (owner_user_id, match_key);

create or replace function public.landing_metrics()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with roll_count as (
    select count(*)::bigint as total_rolls
    from public.rolls
  ),
  top_stock as (
    select
      coalesce(fs.name, '—') as stock_name,
      count(*)::bigint as stock_count
    from public.rolls r
    left join public.film_stocks fs on fs.id = r.film_stock_id
    group by fs.name
    order by count(*) desc, fs.name asc
    limit 1
  ),
  unique_locations as (
    select count(distinct loc)::bigint as unique_locations
    from public.rolls r
    cross join lateral unnest(coalesce(r.locations, '{}'::text[])) as loc
    where nullif(trim(loc), '') is not null
  )
  select jsonb_build_object(
    'totalRolls', (select total_rolls from roll_count),
    'topStockLabel', coalesce((select stock_name from top_stock), '—'),
    'topStockCount', coalesce((select stock_count from top_stock), 0),
    'supportedFormats', 6,
    'uniqueLocations', coalesce((select unique_locations from unique_locations), 0)
  );
$$;

create or replace view public.rolls_flat
with (security_invoker = true)
as
select
  r.id,
  r.code as "#",
  fs.type as "FILM TYPE",
  r.format as "FORMAT",
  case
    when r.fresh is null then null
    when r.fresh then 'FRESH'
    else 'EXPIRED'
  end as "EXP/FRESH",
  fs.name as "FILM STOCK",
  fs.manufacturer as "MANUFACTURER",
  fs.iso as "ISO",
  r.exp_count as "EXP",
  c.maker as "MAKER",
  c.model as "MODEL NAME",
  c.format as "C. FORMAT",
  c.type as "C. TYPE",
  c.mount as "C. MOUNT",
  coalesce(nullif(trim(concat_ws(' ', l.maker, l.model)), ''), r.lens) as "LENS",
  l.mount as "LENS MOUNT",
  array_to_string(r.locations, ', ') as "LOCATIONS",
  array_to_string(r.photo_types, ', ') as "PHOTO TYPE",
  array_to_string(r.tags, ', ') as "TAGS",
  r.iso_pushed as "ISO @",
  to_char(r.started::timestamptz, 'YYYY-MM-DD') as "STARTED",
  to_char(r.finished::timestamptz, 'YYYY-MM-DD') as "FINISHED",
  r.exp_taken as "# EXP",
  r.push_pull as "PUSH/PULL",
  dl.name as "DEV",
  sl.name as "SCAN",
  r.status as "STATUS",
  r.rating as "RATING",
  r.notes as "NOTES",
  r.updated_at,
  coalesce(re_stats.frame_settings_count, 0)::integer as "FRAME SETTINGS"
from public.rolls r
left join public.film_stocks fs on fs.id = r.film_stock_id
left join public.cameras c on c.id = r.camera_id
left join public.lenses l on l.id = r.lens_id
left join public.labs dl on dl.id = r.dev_lab_id
left join public.labs sl on sl.id = r.scan_lab_id
left join lateral (
  select count(*) filter (
    where re.apertura is not null
       or re.shutter_speed is not null
       or coalesce(re.tripie, false)
       or coalesce(re.filtros, false)
       or coalesce(re.flash, false)
       or coalesce(re.luz_natural, false)
       or coalesce(re.multiple_exposures, false)
       or re.notes is not null
  ) as frame_settings_count
  from public.roll_exposures re
  where re.roll_id = r.id
) re_stats on true;

grant usage on schema public to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;

grant select, insert on public.profiles to authenticated;
grant select, insert on public.user_roles to authenticated;
grant select, insert, update on public.film_stocks to authenticated;
grant select, insert, update on public.labs to authenticated;
grant select, insert, update, delete on public.cameras to authenticated;
grant select, insert, update, delete on public.lenses to authenticated;
grant select, insert, update, delete on public.rolls to authenticated;
grant select, insert, update, delete on public.roll_exposures to authenticated;
grant select on public.admin_actions to authenticated;
grant select on public.admin_action_approvals to authenticated;
grant select on public.rolls_flat to authenticated;
revoke all on public.private_app_config from anon, authenticated;
revoke all on public.frame_tags from anon, authenticated;

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.private_app_config enable row level security;
alter table public.film_stocks enable row level security;
alter table public.labs enable row level security;
alter table public.cameras enable row level security;
alter table public.lenses enable row level security;
alter table public.rolls enable row level security;
alter table public.roll_exposures enable row level security;
alter table public.admin_actions enable row level security;
alter table public.admin_action_approvals enable row level security;
alter table public.frame_tags enable row level security;

create policy profiles_self_insert
on public.profiles
for insert
to public
with check (
  user_id = auth.uid()
  and email = auth.jwt() ->> 'email'
  -- 20260526: acepta 'approved' porque ese es el default del registro.
  and status in ('pending', 'approved')
  and rejected_at is null
  and rejected_by is null
);

-- 20260526: el usuario puede actualizar SOLO sus columnas móviles (token de
-- push, preferencias, versión). El grant acotado es la defensa real: la
-- policy sola dejaría tocar cualquier columna.
grant update (
  fcm_token, fcm_platform, fcm_token_updated_at,
  last_mobile_version, last_mobile_seen_at,
  last_terms_accepted_version, last_terms_accepted_at,
  notification_prefs
) on public.profiles to authenticated;

create policy profiles_self_update_mobile
on public.profiles
for update
to public
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy profiles_self_select
on public.profiles
for select
to public
using (user_id = auth.uid());

create policy admin_profiles_select
on public.profiles
for select
to public
using (public.app_is_admin(auth.uid()));

create policy user_roles_self_insert
on public.user_roles
for insert
to public
with check (
  user_id = auth.uid()
  and role = 'user'
  and is_founder = false
  and granted_by is null
);

create policy user_roles_self_select
on public.user_roles
for select
to public
using (user_id = auth.uid());

create policy admin_roles_select
on public.user_roles
for select
to public
using (public.app_is_admin(auth.uid()));

create policy shared_film_stocks_select
on public.film_stocks
for select
to public
using (auth.role() = 'authenticated');

create policy shared_film_stocks_insert
on public.film_stocks
for insert
to public
with check (auth.role() = 'authenticated');

create policy shared_film_stocks_update
on public.film_stocks
for update
to public
using (public.app_is_admin(auth.uid()))
with check (public.app_is_admin(auth.uid()));

create policy shared_labs_select
on public.labs
for select
to public
using (auth.role() = 'authenticated');

create policy shared_labs_insert
on public.labs
for insert
to public
with check (auth.role() = 'authenticated');

create policy shared_labs_update
on public.labs
for update
to public
using (public.app_is_admin(auth.uid()))
with check (public.app_is_admin(auth.uid()));

create policy cameras_owner_select
on public.cameras
for select
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy cameras_owner_insert
on public.cameras
for insert
to public
with check (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy cameras_owner_update
on public.cameras
for update
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
)
with check (owner_user_id = auth.uid());

create policy cameras_owner_delete
on public.cameras
for delete
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy lenses_owner_select
on public.lenses
for select
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy lenses_owner_insert
on public.lenses
for insert
to public
with check (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy lenses_owner_update
on public.lenses
for update
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
)
with check (owner_user_id = auth.uid());

create policy lenses_owner_delete
on public.lenses
for delete
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy rolls_owner_select
on public.rolls
for select
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy rolls_owner_insert
on public.rolls
for insert
to public
with check (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy rolls_owner_update
on public.rolls
for update
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
)
with check (owner_user_id = auth.uid());

create policy rolls_owner_delete
on public.rolls
for delete
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy roll_exposures_owner_select
on public.roll_exposures
for select
to public
using (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy roll_exposures_owner_insert
on public.roll_exposures
for insert
to public
with check (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy roll_exposures_owner_update
on public.roll_exposures
for update
to public
using (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
)
with check (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy roll_exposures_owner_delete
on public.roll_exposures
for delete
to public
using (
  exists (
    select 1
    from public.rolls r
    join public.profiles p on p.user_id = auth.uid()
    where r.id = roll_exposures.roll_id
      and r.owner_user_id = auth.uid()
      and p.status = 'approved'
  )
);

create policy admin_actions_select
on public.admin_actions
for select
to public
using (public.app_is_admin(auth.uid()));

create policy admin_action_approvals_select
on public.admin_action_approvals
for select
to public
using (public.app_is_admin(auth.uid()));

revoke all on function public.app_is_admin(uuid) from public;
revoke all on function public.app_is_founder(uuid) from public;
revoke all on function public.admin_set_profile_status(uuid, text) from public;
revoke all on function public.request_admin_action(text, uuid, text) from public;
revoke all on function public.cancel_admin_action(uuid, text) from public;
revoke all on function public.cast_admin_action_vote(uuid, text) from public;
revoke all on function public.landing_metrics() from public;
revoke all on function public.notify_pending_signup() from public;

grant execute on function public.app_is_admin(uuid) to authenticated;
grant execute on function public.app_is_founder(uuid) to authenticated;
grant execute on function public.admin_set_profile_status(uuid, text) to authenticated;
grant execute on function public.request_admin_action(text, uuid, text) to authenticated;
grant execute on function public.cancel_admin_action(uuid, text) to authenticated;
grant execute on function public.cast_admin_action_vote(uuid, text) to authenticated;
grant execute on function public.landing_metrics() to anon, authenticated;
