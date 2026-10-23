-- Buzón privado (ANA-185): avisos de datos, aviso agrupado de rollos viejos y
-- resolución. Ver BACKEND-BUZON.md, sección 6.
--
-- Un rollo viejo (creado antes de activar el buzón) nunca genera avisos
-- sueltos: lo que le falte aparece en la lista del aviso agrupado. Uno nuevo
-- genera un aviso por faltante, oculto durante 3 días locales por si se
-- completa solo.

-- Avisos sueltos de rollos nuevos: nacer, desaparecer en el margen, mostrarse.
create function app_private.inbox_eval_gaps(p_uid uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := app_private.inbox_local_date(p_uid, p_now);
begin
  insert into public.inbox_notices (owner_user_id, kind, roll_id, camera_id, detected_at)
  select p_uid, g.kind, g.roll_id, g.camera_id, p_now
  from app_private.inbox_roll_gaps(p_uid) g
  where not g.is_old
  on conflict do nothing;

  -- Se completó antes de verse: se borra, y si vuelve a faltar empieza otro margen.
  with g as materialized (
    select g.kind, g.roll_id, g.camera_id from app_private.inbox_roll_gaps(p_uid) g where not g.is_old
  )
  delete from public.inbox_notices n
  where n.owner_user_id = p_uid and n.shown_at is null
    and n.kind in ('missing_camera', 'missing_lens', 'missing_lab', 'camera_lens_question')
    and not exists (select 1 from g where g.kind = n.kind
                      and g.roll_id is not distinct from n.roll_id
                      and g.camera_id is not distinct from n.camera_id);

  update public.inbox_notices n
     set shown_at = p_now, rang_at = p_now, read_at = null
   where n.owner_user_id = p_uid and n.shown_at is null
     and n.kind in ('missing_camera', 'missing_lens', 'missing_lab', 'camera_lens_question')
     and v_today >= app_private.inbox_local_date(p_uid, n.detected_at) + 3;
end;
$$;

-- El aviso agrupado de rollos viejos. Suena solo en la activación; si después
-- reaparece, lo hace sin marcarse como sin leer. Descartado, no vuelve.
create function app_private.inbox_eval_backlog(p_uid uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_first boolean := (select a.last_evaluated_on is null from public.inbox_accounts a where a.user_id = p_uid);
begin
  if not exists (select 1 from app_private.inbox_roll_gaps(p_uid) g where g.is_old) then
    return;
  end if;
  insert into public.inbox_notices (owner_user_id, kind, detected_at, shown_at, rang_at, read_at)
  values (p_uid, 'backlog_incomplete', p_now, p_now, p_now, case when v_first then null else p_now end)
  on conflict do nothing;
  update public.inbox_notices n
     set resolved_at = null
   where n.owner_user_id = p_uid and n.kind = 'backlog_incomplete'
     and n.resolved_at is not null and n.dismissed_at is null;
end;
$$;

-- Resolver lo que ya no falta, y reabrir sin leer lo que volvió a faltar. Se
-- llama también al leer el buzón, para no esperar a la revisión diaria.
create function app_private.inbox_resolve(p_uid uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  with g as materialized (
    select g.kind, g.roll_id, g.camera_id from app_private.inbox_roll_gaps(p_uid) g where not g.is_old
  ),
  cur as (
    select n.id,
           exists (select 1 from g where g.kind = n.kind
                     and g.roll_id is not distinct from n.roll_id
                     and g.camera_id is not distinct from n.camera_id) as holds
    from public.inbox_notices n
    where n.owner_user_id = p_uid and n.shown_at is not null
      and n.kind in ('missing_camera', 'missing_lens', 'missing_lab', 'camera_lens_question')
  )
  update public.inbox_notices n
     set resolved_at = case when c.holds then null else p_now end,
         rang_at = case when c.holds then p_now else n.rang_at end,
         read_at = case when c.holds then null else n.read_at end
    from cur c
   where c.id = n.id
     and c.holds = (n.resolved_at is not null);  -- solo los que cambian de estado

  update public.inbox_notices n
     set resolved_at = p_now
   where n.owner_user_id = p_uid and n.kind = 'backlog_incomplete'
     and n.resolved_at is null and n.dismissed_at is null
     and not exists (select 1 from app_private.inbox_roll_gaps(p_uid) g where g.is_old);
end;
$$;

-- Evaluar una cuenta activada. Un candado por cuenta: dos revisiones a la vez
-- esperan una a la otra, y la identidad única impide duplicados de todos modos.
create function app_private.inbox_evaluate(p_uid uuid, p_now timestamptz default now())
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
  perform app_private.inbox_resolve(p_uid, p_now);
  update public.inbox_accounts
     set last_evaluated_on = app_private.inbox_local_date(p_uid, p_now)
   where user_id = p_uid;
end;
$$;

revoke all on function app_private.inbox_eval_gaps(uuid, timestamptz),
  app_private.inbox_eval_backlog(uuid, timestamptz), app_private.inbox_resolve(uuid, timestamptz),
  app_private.inbox_evaluate(uuid, timestamptz) from public, anon, authenticated;
