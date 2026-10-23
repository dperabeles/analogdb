-- Deleted gear keeps its name on the rolls (gear_delete_freeze migration).
--
-- Run inside BEGIN / ROLLBACK, before and right after applying the migration
-- (before it, the first assertion fails: there is no snapshot column). Only
-- synthetic accounts (@equipo.invalid); everything is undone with the
-- transaction. The final RAISE reports success and also rolls back.

alter table public.profiles disable trigger profiles_notify_approved;
alter table public.profiles disable trigger profiles_notify_pending_signup;

create or replace function pg_temp.eq_user(p_tag text)
returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  -- The signup trigger requires a username; the profile is born approved.
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                          raw_app_meta_data, created_at, updated_at, email_confirmed_at)
  values (v, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          p_tag || '@equipo.invalid', jsonb_build_object('username', 'eq_' || p_tag),
          '{}'::jsonb, now(), now(), now());
  return v;
end $$;

-- Act as an account (null = no session), like PostgREST does.
create or replace function pg_temp.como(p_user uuid) returns void language plpgsql as $$
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
create or replace function pg_temp.yo() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

do $$
declare
  a uuid; b uuid; c uuid;
  cam bigint; cam2 bigint; cam_big bigint; cam_blank bigint; cam_plain bigint; cam_costs bigint;
  zl bigint; zl2 bigint; zl_frame bigint;
  r1 bigint; r2 bigint; r3 bigint; r_text bigint; r_frame bigint; r_b bigint; r_blank bigint; r_new bigint;
  r_costs bigint;
  flat record;
  snap jsonb;
  n int;
begin
  a := pg_temp.eq_user('gfa');
  b := pg_temp.eq_user('gfb');
  c := pg_temp.eq_user('gfc');

  insert into public.cameras (owner_user_id, maker, model, format, type, mount, supports_interchangeable_lenses)
  values (a, 'Prueba Eq', 'Cam Uno', '35mm', 'SLR', 'Montura P', false) returning id into cam;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Eq', 'Cam Dos', '120') returning id into cam2;
  insert into public.lenses (owner_user_id, maker, model, mount, is_zoom, focal_min, focal_max, max_aperture)
  values (a, 'Prueba Eq', 'Lente 50', 'Montura P', false, 50, 50, 1.4) returning id into zl;
  insert into public.lenses (owner_user_id, maker, model, mount) values (a, 'Prueba Eq', 'Lente 35', 'Montura P') returning id into zl2;
  insert into public.lenses (owner_user_id, maker, model, mount) values (a, 'Prueba Eq', 'Lente Foto', 'Montura P') returning id into zl_frame;

  insert into public.rolls (owner_user_id, code, camera_id, lens_id, status)
  values (a, 'EQ-R1', cam, zl, 'Archived') returning id into r1;
  insert into public.rolls (owner_user_id, code, camera_id, status) values (a, 'EQ-R2', cam, 'Developed') returning id into r2;
  insert into public.rolls (owner_user_id, code, camera_id, status) values (a, 'EQ-R3', cam2, 'Developed') returning id into r3;
  -- A roll with a catalogue lens AND an old free-text lens (42 such in production).
  insert into public.rolls (owner_user_id, code, camera_id, lens_id, lens, status)
  values (a, 'EQ-RT', cam2, zl2, 'texto viejo 35', 'Archived') returning id into r_text;
  insert into public.rolls (owner_user_id, code, camera_id, status) values (a, 'EQ-RF', cam2, 'Archived') returning id into r_frame;
  insert into public.roll_exposures (roll_id, frame_number, lens_id, lens_source, lens_snapshot)
  values (r_frame, 1, zl_frame, 'frame_selected', jsonb_build_object('version', 1, 'display_name', 'Prueba Eq Lente Foto'));
  -- B's roll forced to point at A's camera (no constraint forbids it; there
  -- are none in production). A's name must never land on B's roll.
  insert into public.rolls (owner_user_id, code, camera_id, status) values (b, 'EQ-RB', cam, 'Archived') returning id into r_b;

  -- Old updated_at, to see the key's `set null` move it.
  alter table public.rolls disable trigger rolls_touch;
  update public.rolls set updated_at = '2020-01-01' where id in (r1, r2, r3);
  alter table public.rolls enable trigger rolls_touch;

  -- ── 1. Deleting a camera keeps its name on the rolls ───────────────────
  perform pg_temp.como(a);
  delete from public.cameras where id = cam;
  select * into flat from public.rolls_flat where id = r1;
  assert flat."CAMERA ID" is null, '1: the key is still emptied by the FK';
  assert flat."MAKER" = 'Prueba Eq' and flat."MODEL NAME" = 'Cam Uno', '1: maker and model survive';
  assert flat."C. FORMAT" = '35mm' and flat."C. TYPE" = 'SLR' and flat."C. MOUNT" = 'Montura P', '1: format, type and mount survive';
  assert flat."CAMERA INTERCHANGEABLE" = false, '1: a fixed-lens camera stays fixed-lens';
  assert flat."CAMERA DELETED" and not flat."LENS DELETED", '1: only the camera is marked deleted';
  assert (select "MODEL NAME" from public.rolls_flat where id = r2) = 'Cam Uno', '1: every roll of the camera';
  perform pg_temp.yo();
  assert (select updated_at > '2020-01-02' from public.rolls where id = r1), '1: the roll was rewritten (updated_at moved)';
  assert (select updated_at = '2020-01-01' from public.rolls where id = r3), '1: a roll of another camera is untouched';
  snap := (select camera_snapshot from public.rolls where id = r1);
  assert snap ->> 'display_name' = 'Prueba Eq Cam Uno' and (snap ->> 'camera_id')::bigint = cam
     and snap -> 'version' = '1'::jsonb and snap ? 'frozen_at', '1: snapshot v1 with the original id';

  -- ── 9. The trash keeps the camera as before ────────────────────────────
  assert exists (select 1 from public.deleted_rows where tabla = 'cameras' and fila_id = cam::text and dueno = a),
    '9: the deleted camera is archived';

  -- ── 6. Isolation ───────────────────────────────────────────────────────
  assert (select camera_id is null and camera_snapshot is null from public.rolls where id = r_b),
    '6: B''s roll loses the link but never gets A''s camera name';
  perform pg_temp.como(b);
  assert not exists (select 1 from public.rolls_flat where "#" like 'EQ-R%' and id <> r_b), '6: B sees none of A''s rolls';
  assert (select "MAKER" is null from public.rolls_flat where id = r_b), '6: B sees no name on its roll';
  -- Without a session the rolls policy cannot even read profiles: a denial
  -- (as today, before this migration) or zero rows both mean "sees nothing".
  perform pg_temp.como(null);
  begin
    select count(*) into n from public.rolls_flat where "#" like 'EQ-%';
    assert n = 0, '6: no session sees nothing';
  exception when insufficient_privilege then null;
  end;
  perform pg_temp.como(a);
  assert (select count(*) from public.rolls_flat where "#" like 'EQ-%') = 5, '6: A sees exactly its 5 rolls';

  -- ── 2. Deleting a lens: the catalogue name wins over the old text ───────
  delete from public.lenses where id = zl2;
  select * into flat from public.rolls_flat where id = r_text;
  assert flat."LENS ID" is null and flat."LENS" = 'Prueba Eq Lente 35', '2: LENS shows the frozen catalogue name';
  assert flat."LENS MOUNT" = 'Montura P' and flat."LENS DELETED", '2: mount kept and marked deleted';
  perform pg_temp.yo();
  assert (select lens = 'texto viejo 35' from public.rolls where id = r_text), '2: the old free text is untouched';
  assert (select (lens_snapshot ->> 'lens_id')::bigint = zl2 from public.rolls where id = r_text), '2: original lens id kept';

  -- ── 3. Frames keep their own snapshot ──────────────────────────────────
  perform pg_temp.como(a);
  delete from public.lenses where id = zl_frame;
  perform pg_temp.yo();
  assert (select lens_id is null and lens_source = 'frame_selected'
            and lens_snapshot ->> 'display_name' = 'Prueba Eq Lente Foto'
          from public.roll_exposures where roll_id = r_frame and frame_number = 1), '3: the frame keeps name and source';
  perform pg_temp.como(a);
  update public.roll_exposures set apertura = 'f/8' where roll_id = r_frame and frame_number = 1;
  get diagnostics n = row_count;
  assert n = 1, '3: the frame can still be edited';

  -- ── 4. Choosing another piece clears the snapshot; saving does not ─────
  -- What the app sends for such a roll: every field, camera_id still null.
  update public.rolls set camera_id = null, lens_id = zl, notes = 'guardado desde la app' where id = r2;
  perform pg_temp.yo();
  assert (select camera_snapshot is not null from public.rolls where id = r2), '4: saving with the key empty keeps it';
  perform pg_temp.como(a);
  update public.rolls set camera_id = cam2 where id = r2;
  perform pg_temp.yo();
  assert (select camera_snapshot is null from public.rolls where id = r2), '4: choosing another camera clears it';
  assert (select "MODEL NAME" = 'Cam Dos' and not "CAMERA DELETED" from public.rolls_flat where id = r2), '4: the new camera shows';
  perform pg_temp.como(a);
  update public.rolls set lens = 'escrito en la web' where id = r_text;
  perform pg_temp.yo();
  assert (select lens_snapshot is null from public.rolls where id = r_text), '4: typing another lens text clears the lens snapshot';
  assert (select "LENS" = 'escrito en la web' from public.rolls_flat where id = r_text), '4: and the typed text shows';

  -- ── 5. Clients cannot write snapshots ──────────────────────────────────
  perform pg_temp.como(a);
  insert into public.rolls (owner_user_id, code, status, camera_snapshot)
  values (a, 'EQ-RN', 'In Camera', jsonb_build_object('version', 1, 'display_name', 'Inventada')) returning id into r_new;
  update public.rolls set camera_snapshot = jsonb_build_object('version', 1, 'display_name', 'Inventada') where id = r1;
  update public.rolls set lens_snapshot = jsonb_build_object('version', 1, 'display_name', 'Inventado') where id = r3;
  perform pg_temp.yo();
  assert (select camera_snapshot is null from public.rolls where id = r_new), '5: an insert cannot bring a snapshot';
  assert (select camera_snapshot ->> 'display_name' = 'Prueba Eq Cam Uno' from public.rolls where id = r1), '5: nor overwrite one';
  perform pg_temp.como(a);
  update public.rolls set camera_snapshot = null where id = r1;
  perform pg_temp.yo();
  assert (select camera_snapshot is not null from public.rolls where id = r1), '5: nor erase one';
  assert (select lens_snapshot is null from public.rolls where id = r3), '5: nor invent one for a live piece';
  assert not has_function_privilege('authenticated', 'app_private.rolls_freeze_gear()', 'execute'), '5: freeze not callable';
  begin
    update public.rolls set camera_snapshot = '{"display_name": "sin version"}'::jsonb where id = r3;
    assert false, '5: a snapshot without version must be rejected';
  exception when check_violation then null;
  end;

  -- ── 7. The mass-delete brake still lets a busy camera go ───────────────
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Eq', 'Cam Siete') returning id into cam_big;
  insert into public.rolls (owner_user_id, code, camera_id, status)
  select a, 'EQ-B' || g, cam_big, 'Archived' from generate_series(1, 7) g;
  perform pg_temp.como(a);
  delete from public.cameras where id = cam_big;
  get diagnostics n = row_count;
  assert n = 1, '7: deleting a camera with 7 rolls works';
  perform pg_temp.yo();
  assert (select count(*) from public.rolls where code like 'EQ-B%' and camera_snapshot ->> 'model' = 'Cam Siete') = 7,
    '7: all 7 rolls keep the name';

  -- A camera with no name has nothing to keep, and still deletes.
  insert into public.cameras (owner_user_id, maker, model) values (a, null, null) returning id into cam_blank;
  insert into public.rolls (owner_user_id, code, camera_id, status) values (a, 'EQ-RX', cam_blank, 'Archived') returning id into r_blank;
  perform pg_temp.como(a);
  delete from public.cameras where id = cam_blank;
  perform pg_temp.yo();
  assert (select camera_id is null and camera_snapshot is null from public.rolls where id = r_blank), '7: nameless camera';

  -- ── 12. Normal path ────────────────────────────────────────────────────
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Eq', 'Sin rollos') returning id into cam_plain;
  perform pg_temp.como(a);
  update public.cameras set model = 'Sin rollos B' where id = cam_plain;
  delete from public.cameras where id = cam_plain;
  get diagnostics n = row_count;
  assert n = 1, '12: a camera without rolls deletes';
  update public.rolls set status = 'Developed', notes = 'editado' where id = r3;
  get diagnostics n = row_count;
  assert n = 1, '12: editing a roll as a client works';
  delete from public.rolls where id = r_new;
  get diagnostics n = row_count;
  assert n = 1, '12: deleting a roll as a client works';
  perform pg_temp.yo();
  assert (select camera_snapshot is null and lens_snapshot is null from public.rolls where id = r3), '12: live roll untouched';

  -- ── 13. Export: the JSON dump of rolls carries the snapshots ───────────
  assert (select to_jsonb(r) ? 'camera_snapshot' and to_jsonb(r) ? 'lens_snapshot' from public.rolls r where id = r1),
    '13: select * on rolls includes both snapshots';

  -- ── 10. Costs (only where the costs tables exist) ──────────────────────
  if to_regclass('public.equipment_purchases') is not null then
    insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Eq', 'Cam Costos') returning id into cam_costs;
    insert into public.rolls (owner_user_id, code, camera_id, status) values (a, 'EQ-RC', cam_costs, 'Archived') returning id into r_costs;
    execute 'insert into public.equipment_purchases (owner_user_id, kind, camera_id, purchased_on) values ($1, ''camera'', $2, current_date)'
      using a, cam_costs;
    perform pg_temp.como(a);
    delete from public.cameras where id = cam_costs;
    perform pg_temp.yo();
    execute 'select count(*) from public.equipment_purchases where owner_user_id = $1 and camera_id is null and label = ''Prueba Eq Cam Costos'''
      into n using a;
    assert n = 1, '10: the purchase still freezes its label';
    assert (select camera_snapshot ->> 'model' = 'Cam Costos' from public.rolls where id = r_costs), '10: and the roll its camera';
  end if;

  -- ── 8. Closing the account leaves nothing ──────────────────────────────
  insert into public.cameras (owner_user_id, maker, model) values (c, 'Prueba Eq', 'Cam C') returning id into cam;
  insert into public.lenses (owner_user_id, maker, model) values (c, 'Prueba Eq', 'Lente C') returning id into zl;
  insert into public.rolls (owner_user_id, code, camera_id, lens_id, status)
  select c, 'EQ-C' || g, cam, zl, 'Archived' from generate_series(1, 7) g;
  insert into public.roll_exposures (roll_id, frame_number, lens_id, lens_source, lens_snapshot)
  select r.id, g, zl, 'roll_default', jsonb_build_object('version', 1, 'display_name', 'Prueba Eq Lente C')
  from public.rolls r, generate_series(1, 6) g where r.owner_user_id = c and r.code = 'EQ-C1';
  perform pg_temp.como(c);
  perform public.delete_my_account();
  perform pg_temp.yo();
  assert not exists (select 1 from public.rolls where owner_user_id = c), '8: no rolls left';
  assert not exists (select 1 from public.cameras where owner_user_id = c), '8: no cameras left';
  assert not exists (select 1 from public.lenses where owner_user_id = c), '8: no lenses left';
  assert not exists (select 1 from public.deleted_rows where dueno = c), '8: nothing in the trash';

  raise exception 'gear_delete_freeze: all checks passed (rolled back)';
end $$;
