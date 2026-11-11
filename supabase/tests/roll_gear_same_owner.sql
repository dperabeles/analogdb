-- A roll only points at a camera and a lens of its own account
-- (roll_gear_same_owner migration).
--
-- Run inside BEGIN / ROLLBACK, before and right after applying the migration
-- (before it, the first rejection fails: another account's camera is
-- accepted). Only synthetic accounts (@dueno.invalid); everything is undone
-- with the transaction.

alter table public.profiles disable trigger profiles_notify_approved;
alter table public.profiles disable trigger profiles_notify_pending_signup;

create or replace function pg_temp.own_user(p_tag text)
returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  -- The signup trigger requires a username; the profile is born approved.
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                          raw_app_meta_data, created_at, updated_at, email_confirmed_at)
  values (v, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_tag || '@dueno.invalid', jsonb_build_object('username', 'own_' || p_tag),
          '{}'::jsonb, now(), now(), now());
  return v;
end $$;

-- Act as an account, like PostgREST does.
create or replace function pg_temp.como(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  execute 'set local role authenticated';
end $$;

-- Back to the test runner, with no session claims.
create or replace function pg_temp.yo() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- The statement must be rejected because the camera or lens is not the roll
-- owner's. Anything else (accepted, or another error) fails the test.
create or replace function pg_temp.rechaza(p_sql text, p_what text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception '% accepted: %', p_what, p_sql;
exception when check_violation then
  assert sqlerrm = p_what || ' must belong to the owner of the roll', sqlerrm;
end $$;

do $$
declare
  a uuid := pg_temp.own_user('oa');
  b uuid := pg_temp.own_user('ob');
  cam_a bigint; lens_a bigint; cam_b bigint; cam_b2 bigint; lens_b bigint;
  rb bigint; ra bigint; missing bigint;
begin
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Dueno', 'Cam A') returning id into cam_a;
  insert into public.lenses (owner_user_id, maker, model, mount) values (a, 'Prueba Dueno', 'Lente A', 'M') returning id into lens_a;
  insert into public.cameras (owner_user_id, maker, model) values (b, 'Prueba Dueno', 'Cam B') returning id into cam_b;
  insert into public.cameras (owner_user_id, maker, model) values (b, 'Prueba Dueno', 'Cam B Dos') returning id into cam_b2;
  insert into public.lenses (owner_user_id, maker, model, mount) values (b, 'Prueba Dueno', 'Lente B', 'M') returning id into lens_b;
  missing := (select max(id) + 1000 from public.cameras);

  -- ── From the app, as B ─────────────────────────────────────────────────
  perform pg_temp.como(b);
  -- Its own gear saves as always.
  insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id, lens_id)
  values (b, 'OWN-B1', gen_random_uuid(), 'Archived', cam_b, lens_b) returning id into rb;
  update public.rolls set camera_id = cam_b2 where id = rb;
  -- A's camera or lens is rejected, on insert and on update.
  perform pg_temp.rechaza(format(
    'insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id) values (%L, %L, gen_random_uuid(), %L, %s)',
    b, 'OWN-B2', 'Archived', cam_a), 'Camera');
  perform pg_temp.rechaza(format(
    'insert into public.rolls (owner_user_id, code, client_uuid, status, lens_id) values (%L, %L, gen_random_uuid(), %L, %s)',
    b, 'OWN-B3', 'Archived', lens_a), 'Lens');
  perform pg_temp.rechaza(format('update public.rolls set camera_id = %s where id = %s', cam_a, rb), 'Camera');
  perform pg_temp.rechaza(format('update public.rolls set lens_id = %s where id = %s', lens_a, rb), 'Lens');
  -- A camera that does not exist answers the same: no way to probe for ids.
  perform pg_temp.rechaza(format('update public.rolls set camera_id = %s where id = %s', missing, rb), 'Camera');
  -- Saving the roll without touching its gear still works.
  update public.rolls set notes = 'nota' where id = rb;
  perform pg_temp.yo();
  assert (select (camera_id, lens_id, notes) from public.rolls where id = rb) = (cam_b2, lens_b, 'nota'::text),
         'B keeps its own gear';
  assert not exists (select 1 from public.rolls where code in ('OWN-B2', 'OWN-B3')), 'nothing else was written';

  -- ── The server is held to it too ───────────────────────────────────────
  perform pg_temp.rechaza(format(
    'insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id) values (%L, %L, gen_random_uuid(), %L, %s)',
    b, 'OWN-B4', 'Archived', cam_a), 'Camera');
  -- Handing a roll to another account with its gear behind is rejected.
  perform pg_temp.rechaza(format('update public.rolls set owner_user_id = %L where id = %s', a, rb), 'Camera');

  -- ── Deleting gear and accounts works as before ─────────────────────────
  perform pg_temp.como(b);
  delete from public.cameras where id = cam_b2;
  perform pg_temp.yo();
  assert (select camera_id is null and lens_id = lens_b from public.rolls where id = rb), 'the key still empties the camera';
  -- A, deleted from the dashboard with a roll created in this same transaction.
  insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id, lens_id)
  values (a, 'OWN-A1', gen_random_uuid(), 'Archived', cam_a, lens_a) returning id into ra;
  delete from auth.users where id = a;
  assert not exists (select 1 from public.rolls where id = ra), 'A is gone with its roll';
  -- B closes its account from the app.
  perform pg_temp.como(b);
  perform public.delete_my_account();
  perform pg_temp.yo();
  assert not exists (select 1 from auth.users where id in (a, b)), 'both accounts deleted';
end $$;
