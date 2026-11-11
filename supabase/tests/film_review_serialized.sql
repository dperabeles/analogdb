-- Run after the migration, in a transaction that ends in RAISE (nothing stays).
-- It runs the reviews one after the other: it shows each call's outcome, not
-- two transactions racing (the per-name lock rules that out by construction).
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table zz_ids on commit drop as
select gen_random_uuid() adm, gen_random_uuid() a, gen_random_uuid() b, gen_random_uuid() c, null::bigint fa, null::bigint fb;
grant select on zz_ids to authenticated;
do $$
declare z record;
begin
  select * into z from zz_ids;
  alter table public.profiles disable trigger profiles_notify_approved;
  alter table public.profiles disable trigger profiles_notify_pending_signup;
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  select u, 'zz-'||u||'@example.invalid', jsonb_build_object('username','zz'||substr(replace(u::text,'-',''),1,12)), 'authenticated','authenticated'
    from unnest(array[z.adm, z.a, z.b, z.c]) u;
  update public.profiles set status = 'approved' where user_id in (z.adm, z.a, z.b, z.c);
  insert into public.user_roles (user_id, role) values (z.adm, 'admin') on conflict (user_id) do update set role = 'admin';
end $$;
do $$
declare z record; fa bigint; fb bigint; fc bigint; res text := ''; st text;
begin
  select * into z from zz_ids;
  perform set_config('request.jwt.claims', json_build_object('sub', z.a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  fa := public.ensure_film_stock('ZZ Rev', 'Prueba 400');
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', z.b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  fb := public.ensure_film_stock('zz rev', 'prueba  400');
  execute 'reset role';
  assert fa <> fb, 'two private copies';
  -- Admin 1 approves A's copy: B's copy merges.
  perform set_config('request.jwt.claims', json_build_object('sub', z.adm, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  perform public.review_film_stock(fa, 'approved');
  execute 'reset role';
  assert (select status from public.film_stocks where id = fb) = 'merged', 'B merged';
  -- Admin 2 approves B's copy after waiting: it is already merged.
  perform set_config('request.jwt.claims', json_build_object('sub', z.adm, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.review_film_stock(fb, 'approved');
  exception when others then
    res := res || 'aprobar una copia ya fusionada falla: ' || sqlerrm || '; ';
  end;
  -- Rejecting it is still a mistake worth telling.
  begin
    perform public.review_film_stock(fb, 'rejected');
    res := res || 'rechazar una copia ya fusionada no avisa; ';
  exception when others then null;
  end;
  execute 'reset role';
  -- A copy asked for after the approval gets the approved film.
  perform set_config('request.jwt.claims', json_build_object('sub', z.c, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  fc := public.ensure_film_stock('ZZ REV', 'Prueba 400');
  execute 'reset role';
  if fc <> fa then res := res || 'la copia nueva no recibe el aprobado; '; end if;
  -- A normal user cannot review.
  perform set_config('request.jwt.claims', json_build_object('sub', z.c, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.review_film_stock(fc, 'rejected');
    res := res || 'un usuario normal pudo revisar; ';
  exception when others then
    if sqlerrm <> 'admin only' then res := res || 'error inesperado: ' || sqlerrm || '; '; end if;
  end;
  execute 'reset role';
  -- Both functions take the per-name lock.
  if position('pg_advisory_xact_lock' in pg_get_functiondef('public.review_film_stock(bigint,text)'::regprocedure)) = 0 then res := res || 'review sin candado; '; end if;
  if position('pg_advisory_xact_lock' in pg_get_functiondef('public.ensure_film_stock(text,text,integer,text)'::regprocedure)) = 0 then res := res || 'ensure sin candado; '; end if;
  raise exception 'RESULTADO: %', case when res = '' then 'OK' else res end;
end $$;
