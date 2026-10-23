-- Helpers for the inbox tests (inbox_*.sql). Run them in the same transaction,
-- right before the test file, inside BEGIN / ROLLBACK. Everything here lives in
-- pg_temp and disappears with the transaction. Synthetic accounts use
-- @buzon.invalid so a leftover is easy to count.

-- New profiles would queue signup/approval e-mails through pg_net.
alter table public.profiles disable trigger profiles_notify_approved;
alter table public.profiles disable trigger profiles_notify_pending_signup;

create function pg_temp.buzon_user(p_tag text, p_status text default 'approved',
                                   p_tz text default null)
returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  -- The signup trigger requires a username; the profile is born approved.
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                          raw_app_meta_data, created_at, updated_at, email_confirmed_at)
  values (v, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_tag || '@buzon.invalid', jsonb_build_object('username', 'buzon_' || p_tag),
          '{}'::jsonb, now(), now(), now());
  update public.profiles set timezone = p_tz where user_id = v;
  if p_status <> 'approved' then
    update public.profiles
       set status = p_status, approved_at = null,
           rejected_at = case when p_status = 'rejected' then now() end
     where user_id = v;
  end if;
  return v;
end $$;

create function pg_temp.buzon_admin(p_user uuid) returns void language plpgsql as $$
begin
  insert into public.user_roles (user_id, role) values (p_user, 'admin')
  on conflict (user_id) do update set role = 'admin';
end $$;

create function pg_temp.buzon_camera(p_owner uuid, p_mount text default null,
                                     p_interchangeable boolean default true)
returns bigint language plpgsql as $$
declare v bigint;
begin
  insert into public.cameras (owner_user_id, maker, model, type, mount, supports_interchangeable_lenses)
  values (p_owner, 'Test', 'Cam ' || substr(md5(random()::text), 1, 6), 'P&S', p_mount, p_interchangeable)
  returning id into v;
  return v;
end $$;

create function pg_temp.buzon_lens(p_owner uuid) returns bigint language plpgsql as $$
declare v bigint;
begin
  insert into public.lenses (owner_user_id, maker, model)
  values (p_owner, 'Test', 'Lens ' || substr(md5(random()::text), 1, 6))
  returning id into v;
  return v;
end $$;

create function pg_temp.buzon_roll(p_owner uuid, p_status text, p_camera bigint default null,
                                   p_lens bigint default null)
returns bigint language plpgsql as $$
declare v bigint;
begin
  insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id, lens_id)
  values (p_owner, 'R' || (100 + floor(random() * 899))::int, gen_random_uuid(), p_status, p_camera, p_lens)
  returning id into v;
  return v;
end $$;

-- Act as an account (null = no session), like PostgREST does.
create function pg_temp.como(p_user uuid) returns void language plpgsql as $$
begin
  if p_user is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    execute 'set local role authenticated';
  end if;
end $$;

-- Back to the test runner, with no session claims.
create function pg_temp.yo() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- The statement must fail with exactly this SQLSTATE; its effects are undone.
create function pg_temp.espera_error(p_sql text, p_state text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_state then return; end if;
    raise exception 'esperaba % y llegó % (%) en: %', p_state, sqlstate, sqlerrm, p_sql;
  end;
  raise exception 'esperaba % y no hubo error en: %', p_state, p_sql;
end $$;
