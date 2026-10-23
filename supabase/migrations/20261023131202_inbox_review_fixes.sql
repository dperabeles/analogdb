-- Buzón privado (ANA-185): correcciones de la revisión final y equipo borrado
-- por nombres guardados.
--
-- 1. Equipo borrado. Diego decidió el 22-oct que el buzón use los nombres que
--    gear_delete_freeze guarda en el rollo (camera_snapshot, lens_snapshot) en
--    vez de inbox_suppressions. Se van la tabla y sus dos disparadores.
-- 2. Cámaras ajenas. rolls.camera_id no verifica dueño, así que otra cuenta
--    podía apuntar un rollo suyo a tu cámara y cambiar lo que se sabe de ella
--    (o aprender algo). Ahora solo cuentan los rollos del dueño de la cámara, y
--    un rollo que apunta a una cámara ajena no genera nada.
-- 3. La revisión diaria ya no falla en silencio: el error de una cuenta queda
--    en inbox_accounts, y una preferencia rara ya no rompe el buzón.
-- 4. Quién publicó una política no se lee: es el id de una cuenta.
-- 5. Los avisos de un rollo traen la cámara de ese rollo, como en el plan.

alter table public.inbox_accounts
  add column last_error text,
  add column last_error_at timestamptz;

-- Un rollo tiene lente si lo tiene el rollo (id, texto viejo o el nombre que
-- quedó al borrar el lente) o algún fotograma.
create or replace function app_private.inbox_roll_has_lens(p_roll_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.rolls r
                 where r.id = p_roll_id
                   and (r.lens_id is not null or r.lens_snapshot is not null
                        or nullif(btrim(coalesce(r.lens, '')), '') is not null))
      or exists (select 1 from public.roll_exposures e
                 where e.roll_id = p_roll_id and e.lens_source in ('roll_default', 'frame_selected'));
$$;

-- Igual que antes, pero solo cuentan los rollos del dueño de la cámara.
create or replace function app_private.inbox_camera_kind(p_camera_id bigint)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when c.lens_setup_confirmed_at is not null then
      case when c.supports_interchangeable_lenses then 'interchangeable' else 'fixed' end
    when not c.supports_interchangeable_lenses then 'fixed'
    when exists (select 1 from public.roll_exposures e join public.rolls r on r.id = e.roll_id
                 where r.camera_id = c.id and r.owner_user_id = c.owner_user_id
                   and e.lens_source = 'fixed_camera') then 'fixed'
    when nullif(btrim(coalesce(c.mount, '')), '') is not null then 'interchangeable'
    when exists (select 1 from public.rolls r
                 where r.camera_id = c.id and r.owner_user_id = c.owner_user_id
                   and app_private.inbox_roll_has_lens(r.id)) then 'interchangeable'
    else 'unknown'
  end
  from public.cameras c
  where c.id = p_camera_id;
$$;

-- Sin cámara es sin cámara y sin nombre guardado. Las preguntas y los avisos de
-- lente solo salen de cámaras propias.
create or replace function app_private.inbox_roll_gaps(p_uid uuid)
returns table (kind text, roll_id bigint, camera_id bigint, is_old boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with acct as (
    select coalesce((select a.activated_at from public.inbox_accounts a where a.user_id = p_uid),
                    'infinity'::timestamptz) as activated_at
  ),
  r as (
    select r.id, r.status, r.camera_id, r.camera_snapshot, r.dev_lab_id, r.scan_lab_id,
           r.created_at < (select activated_at from acct) as is_old
    from public.rolls r
    where r.owner_user_id = p_uid and r.status <> 'In Camera'
  ),
  lensless as (
    select r.id, r.camera_id, r.is_old
    from r join public.cameras c on c.id = r.camera_id and c.owner_user_id = p_uid
    where not app_private.inbox_roll_has_lens(r.id)
  ),
  kinds as (
    select k.camera_id, app_private.inbox_camera_kind(k.camera_id) as kind
    from (select distinct l.camera_id from lensless l) k
  )
  select 'missing_camera', r.id, null::bigint, r.is_old
  from r where r.camera_id is null and r.camera_snapshot is null
  union all
  select 'missing_lab', r.id, null::bigint, r.is_old
  from r where r.status in ('Developed', 'Archived') and r.dev_lab_id is null and r.scan_lab_id is null
  union all
  select 'missing_lens', l.id, null::bigint, l.is_old
  from lensless l join kinds k on k.camera_id = l.camera_id where k.kind = 'interchangeable'
  union all
  select 'camera_lens_question', null::bigint, l.camera_id, bool_and(l.is_old)
  from lensless l join kinds k on k.camera_id = l.camera_id where k.kind = 'unknown'
  group by l.camera_id;
$$;

drop trigger inbox_suppress_deleted_camera on public.cameras;
drop trigger inbox_suppress_deleted_lens on public.lenses;
drop function app_private.inbox_suppress_deleted_gear();
drop table public.inbox_suppressions;

-- Cualquier valor que no sea un "no" claro cuenta como encendido.
create or replace function app_private.inbox_reminders_on(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select lower(btrim(p.notification_prefs ->> 'roll_reminders'))
                          not in ('false', 'f', '0', 'no', 'off')
                   from public.profiles p where p.user_id = p_uid), true);
$$;

create or replace function app_private.inbox_evaluate(p_uid uuid, p_now timestamptz default now())
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.inbox_accounts a where a.user_id = p_uid) then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtext('inbox:' || p_uid::text));
  perform app_private.inbox_eval_gaps(p_uid, p_now);
  perform app_private.inbox_eval_backlog(p_uid, p_now);
  perform app_private.inbox_eval_develop(p_uid, p_now);
  perform app_private.inbox_resolve(p_uid, p_now);
  perform app_private.inbox_cleanup(p_uid, p_now);
  update public.inbox_accounts
     set last_evaluated_on = app_private.inbox_local_date(p_uid, p_now),
         last_error = null, last_error_at = null
   where user_id = p_uid;
end;
$$;

-- Una cuenta que falla queda anotada con su error y se reintenta en la
-- siguiente vuelta; no detiene a las demás.
create or replace function app_private.inbox_tick(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_count integer := 0;
begin
  for v_uid in
    select a.user_id from public.inbox_accounts a
    where (p_now at time zone app_private.inbox_zone(a.user_id))::time >= time '08:00'
      and (a.last_evaluated_on is null
           or a.last_evaluated_on < app_private.inbox_local_date(a.user_id, p_now))
  loop
    begin
      perform app_private.inbox_evaluate(v_uid, p_now);
      v_count := v_count + 1;
    exception when others then
      update public.inbox_accounts
         set last_error = left(sqlstate || ': ' || sqlerrm, 500), last_error_at = p_now
       where user_id = v_uid;
      raise warning 'inbox_tick: % falló: % %', v_uid, sqlstate, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

-- Igual que antes; la cámara de un aviso de rollo, y de cada rollo de las
-- listas, sale del rollo.
create or replace function app_private.inbox_payload(p_uid uuid, p_now timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with roll_json as (
    select r.id, r.camera_id,
           jsonb_build_object('id', r.id, 'code', r.code, 'film_stock_id', r.film_stock_id,
                              'camera_id', r.camera_id) as j
    from public.rolls r where r.owner_user_id = p_uid
  ),
  camera_json as (
    select c.id, jsonb_build_object('id', c.id, 'maker', c.maker, 'model', c.model) as j
    from public.cameras c where c.owner_user_id = p_uid
  ),
  develop_items as (
    select coalesce(jsonb_agg(jsonb_build_object('kind', 'to_develop', 'roll', rj.j, 'camera', cj.j,
                                                 'started_at', w.started_at)
                              order by w.started_at, w.roll_id), '[]'::jsonb) as j
    from app_private.inbox_develop_waiting(p_uid, p_now) w
    join roll_json rj on rj.id = w.roll_id
    left join camera_json cj on cj.id = rj.camera_id
  ),
  backlog_items as (
    select coalesce(jsonb_agg(jsonb_build_object('kind', g.kind, 'roll', rj.j, 'camera', cj.j)
                              order by g.kind, g.roll_id, g.camera_id), '[]'::jsonb) as j
    from app_private.inbox_roll_gaps(p_uid) g
    left join roll_json rj on rj.id = g.roll_id
    left join camera_json cj on cj.id = coalesce(g.camera_id, rj.camera_id)
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
      left join camera_json cj on cj.id = coalesce(n.camera_id, rj.camera_id)
      left join public.inbox_policy_notices p on p.id = n.policy_id), '[]'::jsonb),
    'admin', app_private.inbox_admin_block(p_uid),
    'seen_keys', coalesce((select jsonb_agg(s.key order by s.key) from public.inbox_seen_keys s
                           where s.user_id = p_uid), '[]'::jsonb));
$$;

-- La política se lee sin saber qué cuenta la publicó.
revoke select on public.inbox_policy_notices from authenticated;
grant select (id, title_es, title_en, summary_es, summary_en, url, effective_on, published_at)
  on public.inbox_policy_notices to authenticated;
