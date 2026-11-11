-- Films added outside the catalog: one name, many private copies.
--
-- Each account may keep its own copy of a film under review, whatever name
-- another account used. A name is compared without case or extra spaces.
-- Approving a copy merges it into the catalog film of that name when there
-- is one, and every other copy of the name merges into the approved film:
-- rolls, stock, purchases and favourites move with it and nobody is told.
-- Nothing is deleted: a merged film stays, marked, pointing at its target.
-- Only pending films are reviewed, and a roll or a favourite never points
-- at another account's private film.

create or replace function app_private.film_stock_key(p_manufacturer text, p_name text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select lower(regexp_replace(
    btrim(coalesce(p_manufacturer, '') || ' ' || coalesce(p_name, '')),
    '\s+', ' ', 'g'))
$function$;

-- Pure text: ensure_film_stock runs as its caller and needs it.
grant execute on function app_private.film_stock_key(text, text) to authenticated;

alter table public.film_stocks
  add column merged_into bigint references public.film_stocks (id),
  drop constraint film_stocks_status_check,
  add constraint film_stocks_status_check
    check (status in ('pending', 'approved', 'rejected', 'merged'));

-- Moves everything that points at p_from to p_into and marks p_from merged.
create or replace function app_private.merge_film_stock(p_from bigint, p_into bigint)
 returns void
 language plpgsql
 set search_path to ''
as $function$
begin
  update public.rolls set film_stock_id = p_into where film_stock_id = p_from;
  update public.film_units
     set film_stock_id = p_into, version = version + 1
   where film_stock_id = p_from;
  update public.film_purchases set film_stock_id = p_into where film_stock_id = p_from;
  update public.profile_preferences
     set favorite_film_stock_id = p_into
   where favorite_film_stock_id = p_from;
  update public.film_stocks
     set status = 'merged', merged_into = p_into,
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_from;
end;
$function$;

revoke all on function app_private.merge_film_stock(bigint, bigint) from public;

-- The films that exist are all approved; the ones that share a name merge
-- into the catalog's, or else the oldest.
do $$
declare
  r record;
begin
  for r in
    select id, winner from (
      select id,
             first_value(id) over (
               partition by app_private.film_stock_key(manufacturer, name)
               order by in_catalog desc, id) as winner
      from public.film_stocks
      where status = 'approved'
    ) ranked
    where id <> winner
  loop
    perform app_private.merge_film_stock(r.id, r.winner);
  end loop;
end $$;

alter table public.film_stocks drop constraint film_stocks_manufacturer_name_key;

create unique index film_stocks_approved_key on public.film_stocks
  (app_private.film_stock_key(manufacturer, name))
  where status = 'approved';

create unique index film_stocks_own_key on public.film_stocks
  (created_by, app_private.film_stock_key(manufacturer, name))
  where status in ('pending', 'rejected');

-- A merged copy is gone for its creator: their things point at the
-- approved film now.
drop policy shared_film_stocks_select on public.film_stocks;
create policy shared_film_stocks_select on public.film_stocks
  for select
  using (
    auth.role() = 'authenticated'
    and (status = 'approved'
         or (created_by = auth.uid() and status in ('pending', 'rejected'))
         or public.app_is_admin(auth.uid()))
  );

-- The film for a name: the approved one, or the caller's own copy, or a
-- new copy of theirs. Never another account's copy, and never an error
-- because one exists.
create or replace function public.ensure_film_stock(
  p_manufacturer text, p_name text, p_iso integer default null, p_type text default null)
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

revoke all on function public.ensure_film_stock(text, text, integer, text) from public, anon;
grant execute on function public.ensure_film_stock(text, text, integer, text) to authenticated;

-- Only a pending film is reviewed. Approving merges it into the catalog
-- film of its name when there is one; then every other copy of the name
-- merges into the approved film.
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

  select * into v_film from public.film_stocks where id = p_stock_id for update;
  if not found then
    raise exception 'film stock not found';
  end if;
  if v_film.status <> 'pending' then
    raise exception 'film stock already reviewed';
  end if;

  if p_decision = 'rejected' then
    update public.film_stocks
       set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_stock_id;
    return;
  end if;

  v_key := app_private.film_stock_key(v_film.manufacturer, v_film.name);
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

-- The stock takes a film its owner can see: approved, or their own copy.
create or replace function app_private.check_film_line(p_film_stock_id bigint, p_format integer)
 returns void
 language plpgsql
 stable
 set search_path to ''
as $function$
begin
  if p_format is null or p_format not in (35, 120, 110, 8, 16, 45)
     or not exists (
       select 1 from public.film_stocks s
       where s.id = p_film_stock_id
         and (s.status = 'approved'
              or (s.created_by = auth.uid() and s.status in ('pending', 'rejected')))
     ) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
end;
$function$;

-- A roll points at a film its owner can see.
create or replace function app_private.rolls_film_visible()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if new.film_stock_id is not null and not exists (
    select 1 from public.film_stocks s
    where s.id = new.film_stock_id
      and (s.status = 'approved'
           or (s.created_by = new.owner_user_id and s.status in ('pending', 'rejected')))
  ) then
    raise exception 'Film stock not available' using errcode = '23514';
  end if;
  return new;
end;
$function$;

create trigger rolls_film_visible
  before insert or update of film_stock_id, owner_user_id on public.rolls
  for each row execute function app_private.rolls_film_visible();

-- A favourite film is one its owner can see.
create or replace function public.validate_profile_favorites()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if new.favorite_camera_id is not null and not exists (
    select 1 from public.cameras c
    where c.id = new.favorite_camera_id and c.owner_user_id = new.user_id
  ) then
    raise exception 'Favorite camera must belong to profile owner' using errcode = '23514';
  end if;
  if new.favorite_lens_id is not null and not exists (
    select 1 from public.lenses l
    where l.id = new.favorite_lens_id and l.owner_user_id = new.user_id
  ) then
    raise exception 'Favorite lens must belong to profile owner' using errcode = '23514';
  end if;
  -- Checked when it is set or changed, so an old favourite never blocks
  -- saving the rest of the profile.
  if new.favorite_film_stock_id is not null then
    if tg_op = 'INSERT'
       or new.favorite_film_stock_id is distinct from old.favorite_film_stock_id then
      if not exists (
        select 1 from public.film_stocks s
        where s.id = new.favorite_film_stock_id
          and (s.status = 'approved'
               or (s.created_by = new.user_id and s.status in ('pending', 'rejected')))
      ) then
        raise exception 'Favorite film must be visible to profile owner' using errcode = '23514';
      end if;
    end if;
  end if;
  return new;
end $function$;
