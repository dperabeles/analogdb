-- Second pass on private film copies, after review.
--
-- A merged id stands for the film it merged into, for whoever owned it: a
-- roll or a stock command queued offline before a merge lands on the
-- approved film instead of sticking in the queue. Duplicates merge into the
-- catalog film even when in_catalog is null, and the winner keeps an ISO or
-- type only a loser had. The name key collapses spaces before trimming. A
-- new film carries no merged_into and never claims the catalog, and a
-- favourite that is someone else's private film reads as missing.

drop index public.film_stocks_approved_key;
drop index public.film_stocks_own_key;

create or replace function app_private.film_stock_key(p_manufacturer text, p_name text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select lower(btrim(regexp_replace(
    coalesce(p_manufacturer, '') || ' ' || coalesce(p_name, ''),
    '\s+', ' ', 'g')))
$function$;

alter table public.film_stocks
  add constraint film_stocks_merged_into_check
    check ((status = 'merged') = (merged_into is not null));

-- Approved films of one name merge into the catalog's, or else the oldest;
-- the winner keeps any ISO or type a loser had. A creator's own copies of
-- one name merge into the oldest.
create or replace function app_private.dedupe_film_stocks()
 returns integer
 language plpgsql
 set search_path to ''
as $function$
declare
  g record;
  v_winner bigint;
  v_loser bigint;
  n integer := 0;
begin
  for g in
    select array_agg(id order by (in_catalog is true) desc, id) as ids
      from public.film_stocks
     where status = 'approved'
     group by app_private.film_stock_key(manufacturer, name)
    having count(*) > 1
    union all
    select array_agg(id order by id)
      from public.film_stocks
     where status in ('pending', 'rejected')
     group by created_by, app_private.film_stock_key(manufacturer, name)
    having count(*) > 1
  loop
    v_winner := g.ids[1];
    update public.film_stocks w
       set iso = coalesce(w.iso, (select s.iso from public.film_stocks s
                                   where s.id = any (g.ids[2:]) and s.iso is not null
                                   order by s.id limit 1)),
           type = coalesce(w.type, (select s.type from public.film_stocks s
                                     where s.id = any (g.ids[2:]) and s.type is not null
                                     order by s.id limit 1))
     where w.id = v_winner;
    foreach v_loser in array g.ids[2:] loop
      perform app_private.merge_film_stock(v_loser, v_winner);
      n := n + 1;
    end loop;
  end loop;
  return n;
end;
$function$;

revoke all on function app_private.dedupe_film_stocks() from public;

select app_private.dedupe_film_stocks();

create unique index film_stocks_approved_key on public.film_stocks
  (app_private.film_stock_key(manufacturer, name))
  where status = 'approved';

create unique index film_stocks_own_key on public.film_stocks
  (created_by, app_private.film_stock_key(manufacturer, name))
  where status in ('pending', 'rejected');

-- The film an id stands for, for p_owner: itself when they can see it, or
-- the film it merged into when it was theirs (or nobody's). Null otherwise.
-- The row is share-locked so a merge running now waits or is waited for.
create or replace function app_private.resolve_film_stock(p_id bigint, p_owner uuid)
 returns bigint
 language plpgsql
 set search_path to ''
as $function$
declare
  v public.film_stocks;
  v_id bigint := p_id;
begin
  for i in 1..5 loop
    select * into v from public.film_stocks where id = v_id for key share;
    if not found then
      return null;
    end if;
    if v.status = 'approved'
       or (v.created_by = p_owner and v.status in ('pending', 'rejected')) then
      return v_id;
    end if;
    if v.status = 'merged' and (v.created_by = p_owner or v.created_by is null) then
      v_id := v.merged_into;
    else
      return null;
    end if;
  end loop;
  return null;
end;
$function$;

revoke all on function app_private.resolve_film_stock(bigint, uuid) from public;

-- The stock line a command names: a format the stock takes and a film the
-- caller can use, merged ids resolved.
create or replace function app_private.resolve_film_line(p_film_stock_id bigint, p_format integer)
 returns bigint
 language plpgsql
 set search_path to ''
as $function$
declare
  v_id bigint;
begin
  if p_format is null or p_format not in (35, 120, 110, 8, 16, 45) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  v_id := app_private.resolve_film_stock(p_film_stock_id, auth.uid());
  if v_id is null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  return v_id;
end;
$function$;

revoke all on function app_private.resolve_film_line(bigint, integer) from public;

-- The four stock commands take the resolved film. Only their film check
-- line changes; a body without it stops the migration.
do $$
declare
  f regprocedure;
  d text;
  n integer := 0;
begin
  for f in
    select p.oid::regprocedure from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('inventory_receive', 'inventory_adjust', 'inventory_swap', 'inventory_load')
  loop
    d := pg_get_functiondef(f);
    if position('perform app_private.check_film_line(p_film_stock_id, p_format);' in d) = 0 then
      raise exception 'unexpected body in %', f;
    end if;
    execute replace(d,
      'perform app_private.check_film_line(p_film_stock_id, p_format);',
      'p_film_stock_id := app_private.resolve_film_line(p_film_stock_id, p_format);');
    n := n + 1;
  end loop;
  if n <> 4 then
    raise exception 'expected 4 stock commands, found %', n;
  end if;
end $$;

-- A roll points at a film its owner can use; a merged id becomes its film.
create or replace function app_private.rolls_film_visible()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_id bigint;
begin
  if new.film_stock_id is not null then
    v_id := app_private.resolve_film_stock(new.film_stock_id, new.owner_user_id);
    if v_id is null then
      raise exception 'Film stock not available' using errcode = '23514';
    end if;
    new.film_stock_id := v_id;
  end if;
  return new;
end;
$function$;

-- A favourite film is one its owner can use; a merged id becomes its film.
create or replace function public.validate_profile_favorites()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_id bigint;
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
      v_id := app_private.resolve_film_stock(new.favorite_film_stock_id, new.user_id);
      if v_id is null then
        raise exception 'Favorite film must be visible to profile owner' using errcode = '23514';
      end if;
      new.favorite_film_stock_id := v_id;
    end if;
  end if;
  return new;
end $function$;

-- The profile editor reads someone else's private film as missing (P1005),
-- the same answer as an id that does not exist.
do $$
declare
  f regprocedure := 'app_private.save_profile_edit(boolean,text,text,bigint,bigint,bigint,text,timestamptz)'::regprocedure;
  d text := pg_get_functiondef(f);
  old_line text := 'perform id from public.film_stocks where id=p_favorite_film_stock_id for key share;';
begin
  if position(old_line in d) = 0 then
    raise exception 'unexpected body in %', f;
  end if;
  execute replace(d, old_line,
    'perform id from public.film_stocks where id=p_favorite_film_stock_id'
    || ' and (status=''approved'' or (created_by=uid and status in (''pending'',''rejected'')))'
    || ' for key share;');
end $$;

-- A new film is a plain copy: no merged_into, never in the catalog.
drop policy shared_film_stocks_insert on public.film_stocks;
create policy shared_film_stocks_insert on public.film_stocks
  for insert
  with check (
    auth.role() = 'authenticated'
    and created_by = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and merged_into is null
    and in_catalog is not true
  );
