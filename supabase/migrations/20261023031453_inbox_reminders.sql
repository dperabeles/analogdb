-- Buzón privado (ANA-185): recordatorio de rollos por revelar, limpieza y la
-- revisión diaria. Ver BACKEND-BUZON.md, sección 6.
--
-- Un rollo en Por revelar suena el día 14 y el día 44, contados en fechas
-- locales desde marked_to_develop_at (o desde la activación, si no la tiene).
-- Después la app deja de insistir. Todo va en un solo aviso agrupado que
-- vuelve a "sin leer" cada vez que algún rollo llega a su día.

-- Rollos que llevan 14 días o más en Por revelar, el más viejo primero.
create function app_private.inbox_develop_waiting(p_uid uuid, p_now timestamptz)
returns table (roll_id bigint, started_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  with z as (
    select app_private.inbox_zone(p_uid) as zone,
           (select a.activated_at from public.inbox_accounts a where a.user_id = p_uid) as activated_at
  )
  select r.id, coalesce(r.marked_to_develop_at, z.activated_at)
  from public.rolls r, z
  where r.owner_user_id = p_uid and r.status = 'To Develop'
    and (p_now at time zone z.zone)::date
        >= (coalesce(r.marked_to_develop_at, z.activated_at) at time zone z.zone)::date + 14
  order by 2, r.id;
$$;

create function app_private.inbox_reminders_on(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select (p.notification_prefs ->> 'roll_reminders')::boolean
                   from public.profiles p where p.user_id = p_uid), true);
$$;

create function app_private.inbox_eval_develop(p_uid uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_zone text := app_private.inbox_zone(p_uid);
  v_today date := (p_now at time zone v_zone)::date;
  v_activated timestamptz := (select a.activated_at from public.inbox_accounts a where a.user_id = p_uid);
  v_rang boolean;
begin
  -- Un rollo que salió de Por revelar olvida su cuenta.
  delete from public.inbox_develop_rings d
   where d.owner_user_id = p_uid
     and not exists (select 1 from public.rolls r where r.id = d.roll_id and r.status = 'To Develop');

  if not app_private.inbox_reminders_on(p_uid) then
    return;
  end if;

  with w as (
    select r.id, coalesce(r.marked_to_develop_at, v_activated) as started
    from public.rolls r
    where r.owner_user_id = p_uid and r.status = 'To Develop'
  ),
  t as (
    select w.id, w.started,
           case when v_today >= (w.started at time zone v_zone)::date + 44 then 2
                when v_today >= (w.started at time zone v_zone)::date + 14 then 1
                else 0 end as target,
           -- Si la fecha cambió, el rollo volvió a entrar: cuenta nueva.
           case when d.roll_id is null or d.started_at <> w.started then 0 else d.rings end as prev
    from w left join public.inbox_develop_rings d on d.roll_id = w.id
  ),
  up as (
    insert into public.inbox_develop_rings (roll_id, owner_user_id, started_at, rings)
    select t.id, p_uid, t.started, t.target from t
    on conflict (roll_id) do update
      set started_at = excluded.started_at, rings = excluded.rings
  )
  select exists (select 1 from t where t.target > t.prev) into v_rang;

  if v_rang then
    insert into public.inbox_notices (owner_user_id, kind, detected_at, shown_at, rang_at)
    values (p_uid, 'develop_reminder', p_now, p_now, p_now)
    on conflict do nothing;
    update public.inbox_notices n
       set shown_at = coalesce(n.shown_at, p_now), rang_at = p_now, read_at = null, resolved_at = null
     where n.owner_user_id = p_uid and n.kind = 'develop_reminder';
  end if;
end;
$$;

-- Igual que antes, más el recordatorio: se resuelve si ya no queda ningún
-- rollo con 14 días o más, o si la preferencia está apagada.
create or replace function app_private.inbox_resolve(p_uid uuid, p_now timestamptz)
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

  update public.inbox_notices n
     set resolved_at = p_now
   where n.owner_user_id = p_uid and n.kind = 'develop_reminder' and n.resolved_at is null
     and (not app_private.inbox_reminders_on(p_uid)
          or not exists (select 1 from app_private.inbox_develop_waiting(p_uid, p_now)));
end;
$$;

-- Borra lo resuelto o descartado que lleva 90 días leído. Nunca la política
-- (es la prueba del aviso), ni el agrupado descartado: es la marca de "no
-- volver a mostrar"; sin ella, la revisión lo volvería a crear.
create function app_private.inbox_cleanup(p_uid uuid, p_now timestamptz)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.inbox_notices n
  where n.owner_user_id = p_uid
    and n.kind <> 'policy_change'
    and not (n.kind = 'backlog_incomplete' and n.dismissed_at is not null)
    and (n.resolved_at is not null or n.dismissed_at is not null)
    and n.read_at <= p_now - interval '90 days';
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
     set last_evaluated_on = app_private.inbox_local_date(p_uid, p_now)
   where user_id = p_uid;
end;
$$;

-- Corre cada hora. Evalúa cada cuenta activada una vez al día, en la primera
-- vuelta a partir de las 08:00 de su zona. Una cuenta que falla no detiene a
-- las demás.
create function app_private.inbox_tick(p_now timestamptz default now())
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
      raise warning 'inbox_tick: % falló: % %', v_uid, sqlstate, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function app_private.inbox_develop_waiting(uuid, timestamptz),
  app_private.inbox_reminders_on(uuid), app_private.inbox_eval_develop(uuid, timestamptz),
  app_private.inbox_cleanup(uuid, timestamptz), app_private.inbox_tick(timestamptz)
  from public, anon, authenticated;

select cron.unschedule(j.jobid) from cron.job j where j.jobname = 'inbox_tick';
select cron.schedule('inbox_tick', '7 * * * *', 'select app_private.inbox_tick()');
