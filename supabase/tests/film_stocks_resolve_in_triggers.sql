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
declare z record; r bigint; pa bigint; pb bigint; res text := ''; st text;
begin
  select * into z from zz_ids;
  -- A: plain insert with a catalogue film, then own private film, then update.
  perform set_config('request.jwt.claims', json_build_object('sub', z.a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.rolls (code, owner_user_id, film_stock_id) values ('ZZ-1', z.a, z.s1) returning id into r;
  pa := public.ensure_film_stock('ZZ', 'Privado A');
  insert into public.rolls (code, owner_user_id, film_stock_id) values ('ZZ-2', z.a, pa);
  update public.rolls set film_stock_id = z.s2 where id = r;
  insert into public.profile_preferences (user_id, favorite_film_stock_id) values (z.a, pa)
    on conflict (user_id) do update set favorite_film_stock_id = excluded.favorite_film_stock_id;
  execute 'reset role';
  assert (select film_stock_id from public.rolls where id = r) = z.s2, 'update film';
  assert (select count(*) from public.rolls where owner_user_id = z.a) = 2, 'A rolls';
  assert (select favorite_film_stock_id from public.profile_preferences where user_id = z.a) = pa, 'A favorite';
  res := res || 'A crea rollos con film de catálogo y propio, edita y pone favorito; ';

  -- B: cannot use A's private film, and cannot tell it apart from a missing id.
  perform set_config('request.jwt.claims', json_build_object('sub', z.b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into public.rolls (code, owner_user_id, film_stock_id) values ('ZZ-3', z.b, pa);
    res := res || 'FALLA B usó el film privado de A; ';
  exception when sqlstate '23514' then null; end;
  begin
    insert into public.rolls (code, owner_user_id, film_stock_id) values ('ZZ-4', z.a, pa);
    res := res || 'FALLA B escribió un rollo de A; ';
  exception when others then st := sqlstate; end;
  assert st = '23514', 'B con dueño A y film privado de A debe dar 23514, dio ' || st;
  begin
    insert into public.rolls (code, owner_user_id, film_stock_id) values ('ZZ-5', z.a, 999999999);
  exception when others then st := sqlstate; end;
  assert st = '23514', 'id inexistente debe dar el mismo 23514, dio ' || st;
  begin
    insert into public.profile_preferences (user_id, favorite_film_stock_id) values (z.b, pa)
      on conflict (user_id) do update set favorite_film_stock_id = excluded.favorite_film_stock_id;
    res := res || 'FALLA B puso de favorito el film privado de A; ';
  exception when sqlstate '23514' then null; end;
  insert into public.rolls (code, owner_user_id, film_stock_id) values ('ZZ-6', z.b, z.s1);
  execute 'reset role';
  res := res || 'B no usa ni distingue el film privado de A, y crea su rollo con catálogo; ';

  -- Trigger functions are no longer executable by API roles.
  assert not has_function_privilege('authenticated', 'app_private.rolls_film_visible()', 'execute'), 'exec rolls trg';
  assert not has_function_privilege('anon', 'public.validate_profile_favorites()', 'execute'), 'exec fav trg anon';
  assert not has_function_privilege('authenticated', 'public.validate_profile_favorites()', 'execute'), 'exec fav trg auth';

  raise exception 'ENSAYO FIX OK: ok; %', res;
end $$;
