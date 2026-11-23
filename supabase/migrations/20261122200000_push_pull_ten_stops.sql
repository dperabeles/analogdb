-- Push/pull reaches ten stops either way (Diego, 22-nov-2026): better there
-- for the rare roll that needs it than missing. The scale of thirds keeps
-- doubling every stop past 102400, and under 3 the dial's 2.5, 2, 1.6, 1.25
-- and 1 round to whole numbers with ISO 1 as the floor (rolls refuse less).
-- Same table as the app (lib/features/rolls/data/push_pull.dart).
create or replace function app_private.iso_at_thirds(p_iso integer, p_thirds integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  with scale as (
    select v, i::integer as i
    from unnest(array[1, 1, 2, 2, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 25, 32,
      40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000,
      1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800,
      16000, 20000, 25600, 32000, 40000, 51200, 64000, 80000, 102400, 128000,
      160000, 204800, 256000, 320000, 409600, 512000, 640000, 819200, 1024000,
      1280000, 1638400, 2048000, 2560000, 3276800, 4096000, 5120000,
      6553600]) with ordinality as t(v, i)
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

revoke all on function app_private.iso_at_thirds(integer, integer) from public, anon, authenticated;
