-- Push/pull in thirds of a stop decides the ISO a roll is exposed at
-- (Diego, 22-nov-2026). The app's selector moves a third at a time and shows
-- the ISO it lands on; the base works out the same number when a roll is
-- created or its push/pull or film changes, so the app, the web and the
-- export never disagree. Whole stops stay as every build wrote them ("+1");
-- thirds add the fraction glyph ("+1⅓", "-⅔").

-- Thirds of a stop in a push/pull text; null when it cannot be read.
create or replace function app_private.push_pull_thirds(p text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when m is null or (m[2] = '' and m[3] = '') then null
    else (case when m[1] in ('-', '−') then -1 else 1 end)
         * (coalesce(nullif(m[2], '')::integer, 0) * 3
            + case m[3] when '⅓' then 1 when '⅔' then 2 else 0 end)
  end
  from (select regexp_match(btrim(p), '^([+\-−]?)([0-9]*)([⅓⅔]?)$') as m) s
$$;

-- ISO speeds in thirds of a stop, as camera dials mark them: the same table
-- the app uses (lib/features/rolls/data/push_pull.dart).
create or replace function app_private.iso_at_thirds(p_iso integer, p_thirds integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  with scale as (
    select v, i::integer as i
    from unnest(array[3, 4, 5, 6, 8, 10, 12, 16, 20, 25, 32, 40, 50, 64, 80,
      100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000,
      2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000, 25600,
      32000, 40000, 51200, 64000, 80000, 102400]) with ordinality as t(v, i)
  ), nearest as (
    select i from scale
    order by greatest(v::numeric / p_iso, p_iso::numeric / v), i
    limit 1
  )
  select case when p_thirds = 0 then p_iso
    else (select v from scale
          where i = least(greatest((select i from nearest) + p_thirds, 1),
                          (select max(i) from scale)))
  end
$$;

-- Fills rolls.iso_pushed from the push/pull and the film's ISO. On insert it
-- fills only what came empty (an import may bring its own); on update it
-- works it out again only when the push/pull or the film actually changed,
-- so an unrelated save never rewrites what a roll already had. Security
-- definer: it runs for every account, which have no access to app_private;
-- it reads only the ISO of the film the row already points at (whose
-- visibility rolls_film_visible checks).
create or replace function app_private.rolls_iso_from_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_thirds integer := app_private.push_pull_thirds(new.push_pull);
  v_iso integer;
begin
  if tg_op = 'UPDATE'
     and new.push_pull is not distinct from old.push_pull
     and new.film_stock_id is not distinct from old.film_stock_id then
    return new;
  end if;
  if v_thirds is null then
    return new;
  end if;
  if v_thirds = 0 then
    if tg_op = 'UPDATE' then new.iso_pushed := null; end if;
    return new;
  end if;
  if tg_op = 'INSERT' and new.iso_pushed is not null then
    return new;
  end if;
  select fs.iso into v_iso from public.film_stocks fs where fs.id = new.film_stock_id;
  if v_iso is not null and v_iso > 0 then
    new.iso_pushed := app_private.iso_at_thirds(v_iso, v_thirds);
  end if;
  return new;
end;
$$;

drop trigger if exists rolls_iso_from_push on public.rolls;
create trigger rolls_iso_from_push
  before insert or update of push_pull, film_stock_id on public.rolls
  for each row execute function app_private.rolls_iso_from_push();

revoke all on function app_private.push_pull_thirds(text) from public, anon, authenticated;
revoke all on function app_private.iso_at_thirds(integer, integer) from public, anon, authenticated;
revoke all on function app_private.rolls_iso_from_push() from public, anon, authenticated;
