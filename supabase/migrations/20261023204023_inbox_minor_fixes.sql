-- Buzón (ANA-185): menores de la revisión, 23-oct-2026.
--
-- 1. La política no se borra si alguien ya tiene su aviso: `first_opened_at`
--    es la prueba de que se avisó, y la cascada se la llevaba.
-- 2. La limpieza cuenta 90 días desde que el aviso se resolvió, leído o no
--    (Diego, 23-oct). Antes contaba desde la lectura, y una pregunta contestada
--    desde su tarjeta quedaba resuelta sin leer para siempre.
-- 3. Un cliente no reinicia la cuenta de Por revelar reescribiendo
--    `marked_to_develop_at` mientras el rollo sigue ahí; un reintento del outbox
--    podía regalar un tercer recordatorio. El servidor sí puede fijarla.
-- 4. Un rollo sin `created_at` cuenta como viejo en vez de desaparecer de los
--    avisos sueltos y del agrupado.
-- 5. El bloque de administración dice si la cuenta no es admin, en vez de un
--    null que no distingue "no eres admin" de "algo faltó" (como admin_inbox()).

-- ── 1. La prueba de la política ─────────────────────────────────────────────

alter table public.inbox_notices drop constraint inbox_notices_policy_id_fkey;
alter table public.inbox_notices add constraint inbox_notices_policy_id_fkey
  foreign key (policy_id) references public.inbox_policy_notices (id) on delete restrict;

-- ── 2. Limpieza a los 90 días de resolverse ─────────────────────────────────

create or replace function app_private.inbox_cleanup(p_uid uuid, p_now timestamptz)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.inbox_notices n
  where n.owner_user_id = p_uid
    and n.kind <> 'policy_change'
    and not (n.kind = 'backlog_incomplete' and n.dismissed_at is not null)
    and coalesce(n.resolved_at, n.dismissed_at) <= p_now - interval '90 days';
$$;

-- ── 3. La fecha de Por revelar ──────────────────────────────────────────────

-- SECURITY INVOKER, como antes: `current_user` tiene que ser quien escribe.
create or replace function app_private.rolls_mark_to_develop()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'To Develop' and (tg_op = 'INSERT' or old.status is distinct from 'To Develop') then
    new.marked_to_develop_at := now();
  elsif tg_op = 'UPDATE' and new.status = 'To Develop' and current_user in ('authenticated', 'anon') then
    new.marked_to_develop_at := old.marked_to_develop_at;
  end if;
  return new;
end;
$$;

create or replace trigger rolls_mark_to_develop
before insert or update of status, marked_to_develop_at on public.rolls
for each row execute function app_private.rolls_mark_to_develop();

-- ── 4. Rollos sin fecha de creación ─────────────────────────────────────────

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
           coalesce(r.created_at < (select activated_at from acct), true) as is_old
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

-- ── 5. El bloque de administración ──────────────────────────────────────────

create or replace function app_private.inbox_admin_block(p_uid uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when public.app_is_admin(p_uid) then jsonb_build_object(
    'es_admin', true,
    'labs_pending', (select count(*) from public.labs l where l.status = 'pending'),
    'role_requests', (select count(*) from public.admin_actions x where x.status = 'pending'),
    'has_news', coalesce(
      greatest((select max(l.created_at) from public.labs l where l.status = 'pending'),
               (select max(x.created_at) from public.admin_actions x where x.status = 'pending'))
        > coalesce((select a.admin_read_at from public.inbox_accounts a where a.user_id = p_uid),
                   '-infinity'::timestamptz),
      false))
  else jsonb_build_object('es_admin', false)
  end;
$$;
