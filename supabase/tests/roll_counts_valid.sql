-- Run after the migration, in a transaction that ends in RAISE (nothing stays).
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table zz_ids on commit drop as
select gen_random_uuid() a, gen_random_uuid() b,
       null::bigint s1, null::bigint s2;
grant select on zz_ids to authenticated;
do $$
declare z record;
begin
  select * into z from zz_ids;
  alter table public.profiles disable trigger profiles_notify_approved;
  alter table public.profiles disable trigger profiles_notify_pending_signup;
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
   (z.a, 'zz-a-'||z.a||'@example.invalid', jsonb_build_object('username','zza'||substr(replace(z.a::text,'-',''),1,10)), 'authenticated','authenticated'),
   (z.b, 'zz-b-'||z.b||'@example.invalid', jsonb_build_object('username','zzb'||substr(replace(z.b::text,'-',''),1,10)), 'authenticated','authenticated');
  update public.profiles set status = 'approved' where user_id in (z.a, z.b);
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
    values ('ZZ', 'Catalogo uno', 400, 'COLOR', true, 'approved') returning id into z.s1;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
    values ('ZZ', 'Catalogo dos', 200, 'COLOR', true, 'approved') returning id into z.s2;
  update zz_ids set s1 = z.s1, s2 = z.s2;
end $$;
do $$
declare z record; st text; res text := '';
begin
  select * into z from zz_ids;
  perform set_config('request.jwt.claims', json_build_object('sub', z.a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  foreach st in array array['exp_count = 0', 'exp_count = -2', 'exp_taken = -1', 'iso_pushed = 0'] loop
    begin
      execute format('insert into public.rolls (code, owner_user_id, film_stock_id) values (%L, %L, %s)', 'ZZ-'||md5(st), z.a, z.s1);
      execute format('update public.rolls set %s where code = %L', st, 'ZZ-'||md5(st));
      res := res || 'FALLA aceptó ' || st || '; ';
    exception when check_violation then null;
    end;
  end loop;
  insert into public.rolls (code, owner_user_id, film_stock_id, exp_count, exp_taken, iso_pushed)
    values ('ZZ-OK', z.a, z.s1, 15, 0, 400);
  update public.rolls set exp_taken = 16 where code = 'ZZ-OK';
  execute 'reset role';
  assert (select exp_taken from public.rolls where code = 'ZZ-OK' and owner_user_id = z.a) = 16, 'ok roll';
  begin
    insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status) values ('ZZ', 'Iso cero', 0, 'COLOR', true, 'approved');
    res := res || 'FALLA aceptó film con ISO 0; ';
  exception when check_violation then null;
  end;
  assert res = '', res;
  raise exception 'ENSAYO COUNTS OK: rechaza exp 0/-2, finales -1, ISO@ 0 e ISO 0; acepta 15/0/400 y el +1 a 16';
end $$;
