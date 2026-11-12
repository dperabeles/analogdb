-- ANA-135. Run after 20261112170000_camera_frame_size, in a transaction that
-- ends in RAISE (nothing stays). As an ordinary account, by direct writes,
-- the way the app and the web save a camera.
-- Expected: ENSAYO FRAME SIZE OK.
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
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
   (z.a, 'zz-a-'||z.a||'@example.invalid', jsonb_build_object('username','zza'||substr(replace(z.a::text,'-',''),1,10)), 'authenticated','authenticated'),
   (z.b, 'zz-b-'||z.b||'@example.invalid', jsonb_build_object('username','zzb'||substr(replace(z.b::text,'-',''),1,10)), 'authenticated','authenticated');
  update public.profiles set status = 'approved' where user_id in (z.a, z.b);
end $$;
do $$
declare z record; res text := ''; n int;
begin
  select * into z from zz_ids;
  perform set_config('request.jwt.claims', json_build_object('sub', z.a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  -- A 120 camera keeps its size.
  insert into public.cameras (owner_user_id, maker, model, format, frame_size)
    values (z.a, 'Mamiya', 'ZZ 645', '120', '6x4.5');
  if (select frame_size from public.cameras where model = 'ZZ 645') is distinct from '6x4.5' then
    res := res || 'FALLA 120 perdió 6x4.5; ';
  end if;

  -- Editing it without knowing the column keeps the size.
  update public.cameras set mount = 'Mamiya 645' where model = 'ZZ 645';
  if (select frame_size from public.cameras where model = 'ZZ 645') is distinct from '6x4.5' then
    res := res || 'FALLA editar la montura borró el tamaño; ';
  end if;

  -- Another format never carries a size, on insert or when it changes.
  insert into public.cameras (owner_user_id, maker, model, format, frame_size)
    values (z.a, 'Pentax', 'ZZ 35', '35mm', '6x6');
  if (select frame_size from public.cameras where model = 'ZZ 35') is not null then
    res := res || 'FALLA 35mm guardó tamaño; ';
  end if;
  update public.cameras set format = '35mm' where model = 'ZZ 645';
  if (select frame_size from public.cameras where model = 'ZZ 645') is not null then
    res := res || 'FALLA cambiar a 35mm dejó el tamaño; ';
  end if;

  -- A size sent as the format is saved as 120 with that size.
  insert into public.cameras (owner_user_id, maker, model, format)
    values (z.a, 'Fuji', 'ZZ GW690', '6x9');
  if (select format||'|'||coalesce(frame_size,'-') from public.cameras where model = 'ZZ GW690') is distinct from '120|6x9' then
    res := res || 'FALLA el formato 6x9 no pasó a 120 + 6x9; ';
  end if;

  -- Only the four sizes.
  begin
    insert into public.cameras (owner_user_id, maker, model, format, frame_size)
      values (z.a, 'Linhof', 'ZZ 4x5', '120', '4x5');
    res := res || 'FALLA aceptó 4x5; ';
  exception when check_violation then null;
  end;

  -- The other account sees none of it.
  perform set_config('request.jwt.claims', json_build_object('sub', z.b, 'role', 'authenticated')::text, true);
  select count(*) into n from public.cameras where model like 'ZZ %';
  if n <> 0 then res := res || 'FALLA otra cuenta ve ' || n || ' cámaras; '; end if;
  begin
    update public.cameras set frame_size = '6x7' where owner_user_id = z.a;
    get diagnostics n = row_count;
    if n <> 0 then res := res || 'FALLA otra cuenta editó; '; end if;
  end;

  execute 'reset role';
  assert res = '', res;
  raise exception 'ENSAYO FRAME SIZE OK: 120 conserva el tamaño, un tamaño como formato pasa a 120, otros formatos no lo llevan, solo 4 tamaños, otra cuenta no ve ni edita';
end $$;
