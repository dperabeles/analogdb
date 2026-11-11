-- Buzón privado (ANA-185): qué le falta a cada rollo y qué se sabe de cada
-- cámara. Es la única definición de "dato faltante": la usan la revisión
-- diaria, la resolución al leer y la lista del aviso de rollos viejos.

-- Un rollo tiene lente si lo tiene el rollo (id o el texto viejo) o algún
-- fotograma. En un fotograma cuenta lens_source roll_default o frame_selected:
-- el check de roll_exposures les exige el nombre en lens_snapshot, que se
-- conserva aunque se borre el lente. 'unknown' no es un dato.
create function app_private.inbox_roll_has_lens(p_roll_id bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.rolls r
                 where r.id = p_roll_id
                   and (r.lens_id is not null or nullif(btrim(coalesce(r.lens, '')), '') is not null))
      or exists (select 1 from public.roll_exposures e
                 where e.roll_id = p_roll_id and e.lens_source in ('roll_default', 'frame_selected'));
$$;

-- Qué se sabe de una cámara. supports_interchangeable_lenses vale true por
-- defecto, así que un true no prueba nada; un false sí fue una elección.
--   1. La confirmación del usuario manda.
--   2. Un false explícito, o un fotograma marcado fixed_camera: lente fijo.
--   3. Una montura, o un rollo o fotograma suyo con lente: intercambiable.
--   4. Si no, no se sabe y el buzón pregunta.
create function app_private.inbox_camera_kind(p_camera_id bigint)
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
                 where r.camera_id = c.id and e.lens_source = 'fixed_camera') then 'fixed'
    when nullif(btrim(coalesce(c.mount, '')), '') is not null then 'interchangeable'
    when exists (select 1 from public.rolls r
                 where r.camera_id = c.id and app_private.inbox_roll_has_lens(r.id)) then 'interchangeable'
    else 'unknown'
  end
  from public.cameras c
  where c.id = p_camera_id;
$$;

-- Lo que falta hoy en los rollos de una cuenta que ya salieron de En cámara.
-- is_old: el rollo se creó antes de activar el buzón (sin activar, todos lo
-- son). La pregunta de una cámara es vieja solo si todos sus rollos lo son.
create function app_private.inbox_roll_gaps(p_uid uuid)
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
    select r.id, r.status, r.camera_id, r.dev_lab_id, r.scan_lab_id,
           r.created_at < (select activated_at from acct) as is_old,
           exists (select 1 from public.inbox_suppressions s
                   where s.roll_id = r.id and s.field = 'camera') as sup_camera,
           exists (select 1 from public.inbox_suppressions s
                   where s.roll_id = r.id and s.field = 'lens') as sup_lens
    from public.rolls r
    where r.owner_user_id = p_uid and r.status <> 'In Camera'
  ),
  lensless as (
    select r.id, r.camera_id, r.is_old from r
    where r.camera_id is not null and not r.sup_lens and not app_private.inbox_roll_has_lens(r.id)
  ),
  kinds as (
    select k.camera_id, app_private.inbox_camera_kind(k.camera_id) as kind
    from (select distinct l.camera_id from lensless l) k
  )
  select 'missing_camera', r.id, null::bigint, r.is_old
  from r where r.camera_id is null and not r.sup_camera
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

revoke all on function app_private.inbox_roll_has_lens(bigint), app_private.inbox_camera_kind(bigint),
  app_private.inbox_roll_gaps(uuid) from public, anon, authenticated;
