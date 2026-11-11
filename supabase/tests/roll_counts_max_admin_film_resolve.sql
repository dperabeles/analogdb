-- Run after the migration, in a transaction that ends in RAISE (nothing stays).
-- The admin writes as a security definer function does: its session (auth.uid)
-- without the authenticated role.
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table zz_ids on commit drop as
select gen_random_uuid() adm, gen_random_uuid() a, gen_random_uuid() b;
grant select on zz_ids to authenticated;
do $$
declare z record;
begin
  select * into z from zz_ids;
  alter table public.profiles disable trigger profiles_notify_approved;
  alter table public.profiles disable trigger profiles_notify_pending_signup;
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  select u, 'zz-'||u||'@example.invalid', jsonb_build_object('username','zz'||substr(replace(u::text,'-',''),1,12)), 'authenticated','authenticated'
    from unnest(array[z.adm, z.a, z.b]) u;
  update public.profiles set status = 'approved' where user_id in (z.adm, z.a, z.b);
  insert into public.user_roles (user_id, role) values (z.adm, 'admin') on conflict (user_id) do update set role = 'admin';
end $$;
do $$
declare z record; f bigint; res text := '';
begin
  select * into z from zz_ids;
  -- A's private film and a roll of A's without film.
  perform set_config('request.jwt.claims', json_build_object('sub', z.a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  f := public.ensure_film_stock('ZZ Cap', 'Privado 100');
  insert into public.rolls (code, owner_user_id, exp_count) values ('ZZ-CAP', z.a, 36);
  update public.rolls set exp_count = 100, exp_taken = 100 where code = 'ZZ-CAP';
  begin
    update public.rolls set exp_count = 101 where code = 'ZZ-CAP';
    res := res || 'aceptó 101 exposiciones; ';
  exception when check_violation then null;
  end;
  begin
    update public.rolls set exp_taken = 101 where code = 'ZZ-CAP';
    res := res || 'aceptó 101 tomadas; ';
  exception when check_violation then null;
  end;
  execute 'reset role';
  -- B still cannot use A's private film, on a roll or as a favourite.
  perform set_config('request.jwt.claims', json_build_object('sub', z.b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into public.rolls (code, owner_user_id, film_stock_id) values ('ZZ-B', z.b, f);
    res := res || 'B usó el film privado de A en un rollo; ';
  exception when others then
    if sqlerrm <> 'Film stock not available' then res := res || 'B rollo: ' || sqlerrm || '; '; end if;
  end;
  begin
    insert into public.profile_preferences (user_id, favorite_film_stock_id) values (z.b, f)
      on conflict (user_id) do update set favorite_film_stock_id = excluded.favorite_film_stock_id;
    res := res || 'B usó el film privado de A como favorito; ';
  exception when others then
    if sqlerrm <> 'Favorite film must be visible to profile owner' then res := res || 'B favorito: ' || sqlerrm || '; '; end if;
  end;
  execute 'reset role';
  -- The admin moves A's roll and favourite to A's own private film.
  perform set_config('request.jwt.claims', json_build_object('sub', z.adm, 'role', 'authenticated')::text, true);
  begin
    update public.rolls set film_stock_id = f where code = 'ZZ-CAP' and owner_user_id = z.a;
    if (select film_stock_id from public.rolls where code = 'ZZ-CAP' and owner_user_id = z.a) is distinct from f then
      res := res || 'el rollo de A no quedó con su film; ';
    end if;
  exception when others then
    res := res || 'admin no pudo pasar el rollo de A a su film: ' || sqlerrm || '; ';
  end;
  begin
    insert into public.profile_preferences (user_id, favorite_film_stock_id) values (z.a, f)
      on conflict (user_id) do update set favorite_film_stock_id = excluded.favorite_film_stock_id;
  exception when others then
    res := res || 'admin no pudo poner el favorito de A: ' || sqlerrm || '; ';
  end;
  raise exception 'RESULTADO: %', case when res = '' then 'OK' else res end;
end $$;
