-- Two admins approving copies of the same name at the same time each locked
-- their own copy first and then waited for the other's: Postgres aborted one
-- with a deadlock and that admin saw «No se pudo guardar la decisión». And a
-- copy created while its name was being approved stayed private beside the
-- approved film. Reviews and new copies of a name now take one lock per name
-- first, so they run one after the other. A review that finds its copy
-- already merged by the one before it, and meant to approve it, is done.

create or replace function public.review_film_stock(p_stock_id bigint, p_decision text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_film public.film_stocks;
  v_key text;
  v_target bigint;
  r record;
begin
  if not public.app_is_admin(auth.uid()) then
    raise exception 'admin only';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected';
  end if;

  select app_private.film_stock_key(manufacturer, name) into v_key
    from public.film_stocks where id = p_stock_id;
  if not found then
    raise exception 'film stock not found';
  end if;
  -- One review (or new copy) of a name at a time.
  perform pg_advisory_xact_lock(hashtextextended('film_stock:' || v_key, 0));

  select * into v_film from public.film_stocks where id = p_stock_id for update;
  if v_film.status <> 'pending' then
    -- The review before this one merged it into the approved film.
    if p_decision = 'approved' and v_film.status in ('approved', 'merged') then
      return;
    end if;
    raise exception 'film stock already reviewed';
  end if;

  if p_decision = 'rejected' then
    update public.film_stocks
       set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_stock_id;
    return;
  end if;

  select id into v_target from public.film_stocks
   where status = 'approved'
     and app_private.film_stock_key(manufacturer, name) = v_key
   for update;

  if v_target is null then
    update public.film_stocks
       set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_stock_id;
    v_target := p_stock_id;
  else
    perform app_private.merge_film_stock(p_stock_id, v_target);
  end if;

  for r in
    select id from public.film_stocks
     where id <> v_target
       and status in ('pending', 'rejected')
       and app_private.film_stock_key(manufacturer, name) = v_key
     for update
  loop
    perform app_private.merge_film_stock(r.id, v_target);
  end loop;
end $function$;

create or replace function public.ensure_film_stock(p_manufacturer text, p_name text, p_iso integer default null::integer, p_type text default null::text)
 returns bigint
 language plpgsql
 set search_path to ''
as $function$
declare
  v_key text := app_private.film_stock_key(p_manufacturer, p_name);
  v_id bigint;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P1101';
  end if;
  if v_key = '' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  -- Waits for a review of this name in progress, so it finds the approved
  -- film instead of leaving a private copy beside it.
  perform pg_advisory_xact_lock(hashtextextended('film_stock:' || v_key, 0));
  for i in 1..2 loop
    select s.id into v_id from public.film_stocks s
     where s.status = 'approved'
       and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
    if found then return v_id; end if;
    select s.id into v_id from public.film_stocks s
     where s.created_by = auth.uid() and s.status in ('pending', 'rejected')
       and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
    if found then return v_id; end if;
    begin
      insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
      values (btrim(coalesce(p_manufacturer, '')), btrim(coalesce(p_name, '')),
              p_iso, p_type, false)
      returning id into v_id;
      return v_id;
    exception when unique_violation then
      -- Another request made it first: read it again.
      null;
    end;
  end loop;
  raise exception 'stock_conflict' using errcode = 'P1104';
end;
$function$;
