-- A film someone adds outside the catalog stays theirs until an admin
-- approves it for everyone, as labs do. Nobody is told it is under review:
-- its creator sees and uses it the same whether pending, approved or
-- rejected. Every film that exists today is approved; none is removed.

alter table public.film_stocks
  add column status text not null default 'approved',
  add column created_by uuid references auth.users (id) on delete set null,
  add column reviewed_by uuid references auth.users (id) on delete set null,
  add column reviewed_at timestamptz;

alter table public.film_stocks
  alter column status set default 'pending',
  alter column created_by set default auth.uid(),
  add constraint film_stocks_status_check
    check (status in ('pending', 'approved', 'rejected'));

drop policy shared_film_stocks_select on public.film_stocks;
create policy shared_film_stocks_select on public.film_stocks
  for select
  using (
    auth.role() = 'authenticated'
    and (status = 'approved'
         or created_by = auth.uid()
         or public.app_is_admin(auth.uid()))
  );

-- A new film is its creator's and waits for review, whatever it says.
drop policy shared_film_stocks_insert on public.film_stocks;
create policy shared_film_stocks_insert on public.film_stocks
  for insert
  with check (
    auth.role() = 'authenticated'
    and created_by = auth.uid()
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
  );

create or replace function public.review_film_stock(p_stock_id bigint, p_decision text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  if not public.app_is_admin(auth.uid()) then
    raise exception 'admin only';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected';
  end if;

  update public.film_stocks
     set status = p_decision,
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_stock_id;

  if not found then
    raise exception 'film stock not found';
  end if;
end $function$;

revoke all on function public.review_film_stock(bigint, text) from public, anon;
grant execute on function public.review_film_stock(bigint, text) to authenticated;

-- The admin's count names films waiting too; the keys it had stay.
create or replace function public.admin_inbox()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_labs  int;
  v_roles int;
  v_films int;
begin
  -- No se lanza a propósito (ver arriba): se responde diciendo QUÉ pasa.
  if not public.app_is_admin(auth.uid()) then
    return jsonb_build_object(
      'total', 0,
      'items', jsonb_build_object(),
      'es_admin', false
    );
  end if;

  select count(*) into v_labs  from public.labs          where status = 'pending';
  select count(*) into v_roles from public.admin_actions where status = 'pending';
  select count(*) into v_films from public.film_stocks   where status = 'pending';

  return jsonb_build_object(
    'total', v_labs + v_roles + v_films,
    'items', jsonb_build_object(
      'labs_pending',  v_labs,
      'role_requests', v_roles,
      'films_pending', v_films
    ),
    'es_admin', true
  );
end $function$;

-- The public landing names the most used film: only one everybody can see.
create or replace function public.landing_metrics()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with roll_count as (
    select count(*)::bigint as total_rolls
    from public.rolls
  ),
  top_stock as (
    select
      coalesce(fs.name, '—') as stock_name,
      count(*)::bigint as stock_count
    from public.rolls r
    left join public.film_stocks fs on fs.id = r.film_stock_id
    where fs.id is null or fs.status = 'approved'
    group by fs.name
    order by count(*) desc, fs.name asc
    limit 1
  ),
  unique_locations as (
    select count(distinct loc)::bigint as unique_locations
    from public.rolls r
    cross join lateral unnest(coalesce(r.locations, '{}'::text[])) as loc
    where nullif(trim(loc), '') is not null
  )
  select jsonb_build_object(
    'totalRolls', (select total_rolls from roll_count),
    'topStockLabel', coalesce((select stock_name from top_stock), '—'),
    'topStockCount', coalesce((select stock_count from top_stock), 0),
    'supportedFormats', 6,
    'uniqueLocations', coalesce((select unique_locations from unique_locations), 0)
  );
$function$;

-- The stock takes a film its owner can see: approved, or theirs.
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
         and (s.status = 'approved' or s.created_by = auth.uid())
     ) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
end;
$function$;
