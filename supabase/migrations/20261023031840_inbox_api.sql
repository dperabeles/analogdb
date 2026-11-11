-- Buzón privado (ANA-185): las funciones que llama la app. Ver
-- BACKEND-BUZON.md, sección 7. Todas actúan sobre la cuenta de quien llama, que
-- debe tener sesión y perfil aprobado. Todas son idempotentes: la app puede
-- reintentarlas sin conexión.

-- La primera vez que una cuenta pide el buzón queda activada y se evalúa en
-- ese momento, para que el aviso de rollos viejos aparezca de inmediato.
create function app_private.inbox_activate(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new integer;
begin
  insert into public.inbox_accounts (user_id, activated_at) values (p_uid, now())
  on conflict do nothing;
  get diagnostics v_new = row_count;
  if v_new > 0 then
    perform app_private.inbox_evaluate(p_uid, now());
  end if;
end;
$$;

-- El bloque de administración: se calcula al leer, con el mismo conteo que
-- admin_inbox(). Null para quien no es administrador.
create function app_private.inbox_admin_block(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when public.app_is_admin(p_uid) then jsonb_build_object(
    'labs_pending', (select count(*) from public.labs l where l.status = 'pending'),
    'role_requests', (select count(*) from public.admin_actions x where x.status = 'pending'),
    'has_news', coalesce(
      greatest((select max(l.created_at) from public.labs l where l.status = 'pending'),
               (select max(x.created_at) from public.admin_actions x where x.status = 'pending'))
        > coalesce((select a.admin_read_at from public.inbox_accounts a where a.user_id = p_uid),
                   '-infinity'::timestamptz),
      false))
  end;
$$;

-- Avisos sin leer y sin resolver, más el bloque de administración si tiene novedades.
create function app_private.inbox_unread(p_uid uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select (select count(*)::integer from public.inbox_notices n
          where n.owner_user_id = p_uid and n.shown_at is not null and n.dismissed_at is null
            and n.read_at is null and n.resolved_at is null)
       + case when coalesce((app_private.inbox_admin_block(p_uid) ->> 'has_news')::boolean, false)
              then 1 else 0 end;
$$;

-- La respuesta de inbox_list. Los datos del rollo y de la cámara son los de
-- hoy; la app escribe el texto en el idioma del usuario.
create function app_private.inbox_payload(p_uid uuid, p_now timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with roll_json as (
    select r.id, jsonb_build_object('id', r.id, 'code', r.code, 'film_stock_id', r.film_stock_id,
                                    'camera_id', r.camera_id) as j
    from public.rolls r where r.owner_user_id = p_uid
  ),
  camera_json as (
    select c.id, jsonb_build_object('id', c.id, 'maker', c.maker, 'model', c.model) as j
    from public.cameras c where c.owner_user_id = p_uid
  ),
  develop_items as (
    select coalesce(jsonb_agg(jsonb_build_object('kind', 'to_develop', 'roll', rj.j, 'camera', null,
                                                 'started_at', w.started_at)
                              order by w.started_at, w.roll_id), '[]'::jsonb) as j
    from app_private.inbox_develop_waiting(p_uid, p_now) w
    join roll_json rj on rj.id = w.roll_id
  ),
  backlog_items as (
    select coalesce(jsonb_agg(jsonb_build_object('kind', g.kind, 'roll', rj.j, 'camera', cj.j)
                              order by g.kind, g.roll_id, g.camera_id), '[]'::jsonb) as j
    from app_private.inbox_roll_gaps(p_uid) g
    left join roll_json rj on rj.id = g.roll_id
    left join camera_json cj on cj.id = g.camera_id
    where g.is_old
  ),
  notices as (
    select n.*, (n.kind = 'policy_change' and n.first_opened_at is null) as pinned
    from public.inbox_notices n
    where n.owner_user_id = p_uid and n.shown_at is not null and n.dismissed_at is null
  )
  select jsonb_build_object(
    'unread', app_private.inbox_unread(p_uid),
    'notices', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', n.id, 'kind', n.kind, 'shown_at', n.shown_at, 'rang_at', n.rang_at,
               'read', n.read_at is not null, 'resolved', n.resolved_at is not null, 'pinned', n.pinned,
               'roll', rj.j, 'camera', cj.j,
               'policy', case when p.id is not null then jsonb_build_object(
                 'id', p.id, 'title_es', p.title_es, 'title_en', p.title_en,
                 'summary_es', p.summary_es, 'summary_en', p.summary_en,
                 'url', p.url, 'effective_on', p.effective_on) end,
               'items', case n.kind when 'develop_reminder' then (select j from develop_items)
                                    when 'backlog_incomplete' then (select j from backlog_items) end)
             order by n.pinned desc, n.rang_at desc nulls last, n.id)
      from notices n
      left join roll_json rj on rj.id = n.roll_id
      left join camera_json cj on cj.id = n.camera_id
      left join public.inbox_policy_notices p on p.id = n.policy_id), '[]'::jsonb),
    'admin', app_private.inbox_admin_block(p_uid),
    'seen_keys', coalesce((select jsonb_agg(s.key order by s.key) from public.inbox_seen_keys s
                           where s.user_id = p_uid), '[]'::jsonb));
$$;

create function public.inbox_list()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
begin
  perform app_private.inbox_activate(v_uid);
  perform pg_advisory_xact_lock(hashtext('inbox:' || v_uid::text));
  perform app_private.inbox_resolve(v_uid, now());
  return app_private.inbox_payload(v_uid, now());
end;
$$;

create function public.inbox_unread_count()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
begin
  perform app_private.inbox_activate(v_uid);
  perform pg_advisory_xact_lock(hashtext('inbox:' || v_uid::text));
  perform app_private.inbox_resolve(v_uid, now());
  return app_private.inbox_unread(v_uid);
end;
$$;

-- Leído o sin leer. Los ajenos o inexistentes se ignoran. Abrir una política
-- fija la primera apertura, que es la prueba de que se avisó.
create function public.inbox_mark(p_ids uuid[], p_read boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
  v_count integer;
begin
  if p_ids is null or p_read is null or cardinality(p_ids) > 500 then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;
  update public.inbox_notices n
     set read_at = case when p_read then coalesce(n.read_at, now()) end,
         first_opened_at = case when p_read and n.kind = 'policy_change'
                                then coalesce(n.first_opened_at, now()) else n.first_opened_at end
   where n.owner_user_id = v_uid and n.id = any (p_ids) and n.shown_at is not null
     and ((p_read and (n.read_at is null or (n.kind = 'policy_change' and n.first_opened_at is null)))
          or (not p_read and n.read_at is not null));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Todo leído, incluido el bloque de administración. No cuenta como abrir una política.
create function public.inbox_mark_all_read()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
  v_count integer;
begin
  update public.inbox_notices n
     set read_at = now()
   where n.owner_user_id = v_uid and n.shown_at is not null and n.dismissed_at is null and n.read_at is null;
  get diagnostics v_count = row_count;
  update public.inbox_accounts set admin_read_at = now() where user_id = v_uid;
  return v_count;
end;
$$;

-- El bloque de administración no es un aviso guardado; se marca aparte.
create function public.inbox_mark_admin(p_read boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
begin
  if not public.app_is_admin(v_uid) then
    raise exception 'not_admin' using errcode = 'P1205';
  end if;
  if p_read is null then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;
  update public.inbox_accounts set admin_read_at = case when p_read then now() end where user_id = v_uid;
end;
$$;

-- "No volver a mostrar" del aviso de rollos viejos.
create function public.inbox_dismiss_backlog()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
begin
  update public.inbox_notices n
     set dismissed_at = now()
   where n.owner_user_id = v_uid and n.kind = 'backlog_incomplete' and n.dismissed_at is null;
  return exists (select 1 from public.inbox_notices n
                 where n.owner_user_id = v_uid and n.kind = 'backlog_incomplete' and n.dismissed_at is not null);
end;
$$;

-- La respuesta a «¿Esta cámara usa lentes intercambiables?». Escribe también
-- la columna vieja, para que el resto de la app se comporte igual. No evalúa:
-- si es intercambiable, los avisos de lente nacen en la siguiente revisión.
create function public.inbox_answer_camera_lens(p_camera_id bigint, p_interchangeable boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
begin
  if p_camera_id is null or p_interchangeable is null then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;
  update public.cameras c
     set lens_setup_confirmed_at = now(), supports_interchangeable_lenses = p_interchangeable
   where c.id = p_camera_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'not_found' using errcode = 'P1204';
  end if;
  perform app_private.inbox_resolve(v_uid, now());
end;
$$;

-- Novedades y marcas "Nuevo" vistas.
create function public.inbox_mark_seen(p_keys text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
begin
  if p_keys is null or cardinality(p_keys) > 100
     or exists (select 1 from unnest(p_keys) k where k is null or k !~ '^[a-z0-9._:-]{1,100}$') then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;
  insert into public.inbox_seen_keys (user_id, key)
  select v_uid, k from unnest(p_keys) k
  on conflict do nothing;
end;
$$;

revoke all on function app_private.inbox_activate(uuid), app_private.inbox_admin_block(uuid),
  app_private.inbox_unread(uuid), app_private.inbox_payload(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.inbox_list(), public.inbox_unread_count(), public.inbox_mark(uuid[], boolean),
  public.inbox_mark_all_read(), public.inbox_mark_admin(boolean), public.inbox_dismiss_backlog(),
  public.inbox_answer_camera_lens(bigint, boolean), public.inbox_mark_seen(text[])
  from public, anon;
grant execute on function public.inbox_list(), public.inbox_unread_count(), public.inbox_mark(uuid[], boolean),
  public.inbox_mark_all_read(), public.inbox_mark_admin(boolean), public.inbox_dismiss_backlog(),
  public.inbox_answer_camera_lens(bigint, boolean), public.inbox_mark_seen(text[])
  to authenticated;
