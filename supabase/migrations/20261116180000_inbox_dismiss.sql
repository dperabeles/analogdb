-- Deleting read inbox notices. A notice is hidden with dismissed_at, which
-- already existed for the old-rolls notice. Only read or resolved notices go
-- (resolved ones read as done in the app; a policy
-- notice also has to have been opened, and its row is kept as proof). A
-- deleted notice comes back only when there is something new: the develop
-- reminder rings again, or a fixed gap goes missing again.

create or replace function public.inbox_dismiss(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
  v_count integer;
begin
  if p_ids is null or cardinality(p_ids) > 500 then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;
  update public.inbox_notices n
     set dismissed_at = now()
   where n.owner_user_id = v_uid and n.id = any (p_ids)
     and n.dismissed_at is null and (n.read_at is not null or n.resolved_at is not null)
     and (n.kind <> 'policy_change' or n.first_opened_at is not null);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.inbox_dismiss_read()
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
     set dismissed_at = now()
   where n.owner_user_id = v_uid
     and n.dismissed_at is null and (n.read_at is not null or n.resolved_at is not null)
     and n.shown_at is not null
     and (n.kind <> 'policy_change' or n.first_opened_at is not null);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.inbox_dismiss(uuid[]), public.inbox_dismiss_read() from public, anon;
grant execute on function public.inbox_dismiss(uuid[]), public.inbox_dismiss_read() to authenticated;

-- Versions in force copied from the database, changed only where marked.

CREATE OR REPLACE FUNCTION app_private.inbox_eval_develop(p_uid uuid, p_now timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
       set shown_at = coalesce(n.shown_at, p_now), rang_at = p_now, read_at = null, resolved_at = null,
           dismissed_at = null  -- a new ring brings a deleted reminder back
     where n.owner_user_id = p_uid and n.kind = 'develop_reminder';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION app_private.inbox_resolve(p_uid uuid, p_now timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
         read_at = case when c.holds then null else n.read_at end,
         -- Missing again after being fixed is new: a deleted notice comes back.
         dismissed_at = case when c.holds then null else n.dismissed_at end
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
$function$;

CREATE OR REPLACE FUNCTION app_private.inbox_cleanup(p_uid uuid, p_now timestamp with time zone)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  delete from public.inbox_notices n
  where n.owner_user_id = p_uid
    and n.kind <> 'policy_change'
    and not (n.kind = 'backlog_incomplete' and n.dismissed_at is not null)
    -- Deleted but still true stays: removing it would let the inbox create it
    -- again with nothing new. It goes 90 days after being resolved.
    and n.resolved_at <= p_now - interval '90 days';
$function$;
