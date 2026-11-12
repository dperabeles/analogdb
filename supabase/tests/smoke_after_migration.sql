-- Smoke test to run after EVERY migration, first in staging and then in
-- production, inside a transaction that ends in RAISE (nothing stays).
-- It does what an ordinary account does from the app and the web, by direct
-- table writes and not through security definer RPCs: on 2026-11-11 a
-- trigger without permission broke creating a roll for ~40 minutes because
-- every rehearsal went through RPCs (ANA-191).
--
-- Expected: RESULTADO: OK. Anything else names the step that failed.
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table zz_ids on commit drop as
select gen_random_uuid() a, gen_random_uuid() b;
grant select on zz_ids to authenticated;
do $$
declare z record;
begin
  select * into z from zz_ids;
  alter table public.profiles disable trigger profiles_notify_approved;
  alter table public.profiles disable trigger profiles_notify_pending_signup;
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  select u, 'zz-'||u||'@example.invalid', jsonb_build_object('username','zz'||substr(replace(u::text,'-',''),1,12)), 'authenticated','authenticated'
    from unnest(array[z.a, z.b]) u;
  update public.profiles set status = 'approved' where user_id in (z.a, z.b);
end $$;
do $$
declare z record; f bigint; r bigint; res text := ''; n int;
begin
  select * into z from zz_ids;
  -- An ordinary approved account, as the app and the web are.
  perform set_config('request.jwt.claims', json_build_object('sub', z.a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  begin
    f := public.ensure_film_stock('ZZ Smoke', 'Prueba 200');
  exception when others then res := res || 'film: ' || sqlerrm || '; ';
  end;

  -- Create, as the web and the offline outbox do: a plain insert.
  begin
    insert into public.rolls (code, owner_user_id, film_stock_id, exp_count, exp_taken, status)
      values ('ZZ-SMOKE', z.a, f, 36, 0, 'In Camera') returning id into r;
  exception when others then res := res || 'crear rollo: ' || sqlerrm || '; ';
  end;

  if r is not null then
    -- Edit: the +1 count, notes and status.
    begin
      update public.rolls set exp_taken = 1, notes = 'smoke' where id = r;
      update public.rolls set status = 'To Develop' where id = r;
    exception when others then res := res || 'editar rollo: ' || sqlerrm || '; ';
    end;
    -- A frame.
    begin
      insert into public.roll_exposures (roll_id, frame_number, apertura) values (r, 1, 'f/8');
    exception when others then res := res || 'fotograma: ' || sqlerrm || '; ';
    end;
    -- What the web and the app read: the flat view, by the "#" code.
    begin
      select count(*) into n from public.rolls_flat where "#" = 'ZZ-SMOKE';
      if n <> 1 then res := res || 'rolls_flat ve ' || n || ' filas; '; end if;
    exception when others then res := res || 'leer rolls_flat: ' || sqlerrm || '; ';
    end;
  end if;

  execute 'reset role';
  -- Another account sees none of it.
  perform set_config('request.jwt.claims', json_build_object('sub', z.b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.rolls_flat where "#" = 'ZZ-SMOKE';
  if n <> 0 then res := res || 'otra cuenta ve el rollo; '; end if;
  execute 'reset role';

  -- Delete, with its frame (the cascade must pass the mass-delete brake).
  perform set_config('request.jwt.claims', json_build_object('sub', z.a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  if r is not null then
    begin
      delete from public.rolls where id = r;
      if exists (select 1 from public.rolls where id = r) then res := res || 'el rollo sigue; '; end if;
    exception when others then res := res || 'borrar rollo: ' || sqlerrm || '; ';
    end;
  end if;
  execute 'reset role';

  raise exception 'RESULTADO: %', case when res = '' then 'OK' else res end;
end $$;
