-- Camera catalog moderation (20261121090000): propose, review, edit, merge
-- with preview and undo, lens mounts, and manufacturers that carry their
-- cameras along. Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql.
-- Synthetic accounts only.
do $$
declare
  a uuid; b uuid; p uuid; adm uuid;
  nik bigint; leica bigint; mnt bigint; mnt2 bigint;
  x bigint; y bigint; z bigint; w bigint; a_prop bigint; b_prop bigint; dup bigint;
  cam_ax bigint; cam_ay bigint; cam_bx bigint; cam_bz bigint; cam_aprop bigint; cam_del bigint;
  roll1 bigint; change bigint; preview jsonb; frozen text; f text;
begin
  a := pg_temp.inv_user('cmoda');
  b := pg_temp.inv_user('cmodb');
  p := pg_temp.inv_user('cmodp', 'pending');
  adm := pg_temp.inv_user('cmodadm');
  update public.user_roles set role = 'admin' where user_id = adm;

  insert into public.manufacturers (name, status) values ('Prueba Nikon', 'approved') returning id into nik;
  insert into public.manufacturers (name, status) values ('Prueba Leica', 'approved') returning id into leica;
  insert into public.lens_mounts (name) values ('Prueba F') returning id into mnt;
  insert into public.lens_mounts (name) values ('Prueba F2') returning id into mnt2;
  insert into public.camera_models (manufacturer_id, name, type, format, mount_id, interchangeable, status, source)
  values (nik, 'Prueba X', 'SLR', '35mm', mnt, true, 'approved', 'curada') returning id into x;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (nik, 'Prueba Y', 'SLR', '35mm', 'approved', 'curada') returning id into y;
  insert into public.camera_models (manufacturer_id, name, format, status, source)
  values (nik, 'Prueba Z', '35mm', 'approved', 'curada') returning id into z;
  insert into public.camera_models (manufacturer_id, name, format, status, source)
  values (nik, 'Prueba W', '35mm', 'approved', 'curada') returning id into w;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (leica, 'Prueba M', 'Rangefinder', '35mm', 'approved', 'curada');

  -- ── Proposing needs an approved account and a session ──
  perform pg_temp.como(p);
  perform pg_temp.espera_error(format('select public.propose_camera_model(%s, %L)', nik, 'Algo'), 'P1202');
  perform pg_temp.yo();
  perform pg_temp.como(null);
  perform pg_temp.espera_error(format('select public.propose_camera_model(%s, %L)', nik, 'Algo'), '42501');
  perform pg_temp.yo();

  -- ── A proposes; the same spelling is the same proposal; B never sees it ──
  perform pg_temp.como(a);
  a_prop := public.propose_camera_model(nik, '  FM2   Nueva ', 'SLR', '35mm', null, mnt, true, 1982, 2001);
  assert (select status = 'pending' and created_by = a and name = 'FM2 Nueva' and source = 'usuario'
            from public.camera_models where id = a_prop), 'a pending proposal of A';
  assert public.propose_camera_model(nik, 'fm-2 nueva') = a_prop, 'another spelling finds it';
  assert public.propose_camera_model(nik, 'prueba x') = x, 'an approved one is shared';
  perform pg_temp.espera_error(format(
    'select public.propose_camera_model(%s, %L, %L)', nik, 'Mala', 'reflex'), 'P1103');
  perform pg_temp.espera_error(format(
    'select public.propose_camera_model(%s, %L, null, %L, %L)', nik, 'Mala', '35mm', '{6x6}'), 'P1103');
  perform pg_temp.espera_error(format(
    'select public.propose_camera_model(%s, %L, null, null, null, null, null, 2001, 1990)', nik, 'Mala'), 'P1103');
  insert into public.cameras (owner_user_id, camera_model_id) values (a, a_prop) returning id into cam_aprop;
  perform pg_temp.yo();

  perform pg_temp.como(b);
  assert not exists (select 1 from public.camera_models where id = a_prop), 'B cannot read A''s proposal';
  b_prop := public.propose_camera_model(nik, 'FM2 Nueva');
  assert b_prop <> a_prop, 'B gets her own, so nothing reveals A wrote it';
  perform pg_temp.yo();

  -- ── Only the admin moderates ──
  perform pg_temp.como(a);
  foreach f in array array[
    format('select public.admin_camera_model_update(%s, %s, %L, null, null, null, null, null, null, null)', x, nik, 'Hack'),
    format('select public.admin_camera_model_review(%s, %L)', a_prop, 'approved'),
    format('select public.admin_camera_model_merge_preview(%s, %s)', z, w),
    format('select public.admin_camera_model_merge(%s, %s)', z, w),
    'select public.admin_camera_model_undo_merge(1)',
    format('select public.admin_lens_mount_update(%s, %L)', mnt, 'Hack'),
    format('select public.admin_lens_mount_merge(%s, %s)', mnt2, mnt),
    'select public.admin_lens_mount_undo_merge(1)'] loop
    perform pg_temp.espera_error(f, 'P1205');
  end loop;
  perform pg_temp.yo();

  -- ── Rejected: still A's, still hidden from B ──
  perform pg_temp.como(adm);
  perform public.admin_camera_model_review(a_prop, 'rejected');
  perform pg_temp.yo();
  perform pg_temp.como(a);
  assert exists (select 1 from public.camera_models where id = a_prop and status = 'rejected'), 'A still sees it';
  assert (select model from public.cameras where id = cam_aprop) = 'FM2 Nueva', 'and her camera is as it was';
  update public.cameras set show_in_quick_mode = false where id = cam_aprop;
  perform pg_temp.yo();
  perform pg_temp.como(b);
  assert not exists (select 1 from public.camera_models where id = a_prop), 'B still cannot';
  perform pg_temp.yo();

  -- ── Cameras of two people on X; an edit reaches both, logged ──
  insert into public.cameras (owner_user_id, camera_model_id) values (a, x) returning id into cam_ax;
  insert into public.cameras (owner_user_id, camera_model_id) values (a, y) returning id into cam_ay;
  insert into public.cameras (owner_user_id, camera_model_id) values (b, x) returning id into cam_bx;
  insert into public.cameras (owner_user_id, camera_model_id) values (b, z) returning id into cam_bz;

  perform pg_temp.como(adm);
  change := public.admin_camera_model_update(x, nik, 'Prueba X2', 'SLR', '35mm', null, mnt, true, 1977, null);
  perform pg_temp.yo();
  assert (select model from public.cameras where id = cam_ax) = 'Prueba X2'
     and (select model from public.cameras where id = cam_bx) = 'Prueba X2', 'both cameras follow the edit';
  assert (select before ->> 'name' = 'Prueba X' and after ->> 'name' = 'Prueba X2' and changed_by = adm
            from public.catalog_changes where id = change), 'the log has the real before';

  -- An edit that would give A two equal cameras fails and changes nothing.
  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format(
    'select public.admin_camera_model_update(%s, %s, %L, null, %L, null, null, null, null, null)',
    y, nik, 'Prueba X2', '35mm'), 'P1113');
  perform pg_temp.yo();

  -- A rename that would make A's camera equal to one she typed by hand.
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Nikon', 'Prueba Q');
  insert into public.camera_models (manufacturer_id, name, format, status, source)
  values (nik, 'Prueba V', '35mm', 'approved', 'curada') returning id into dup;
  insert into public.cameras (owner_user_id, camera_model_id) values (a, dup);
  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format(
    'select public.admin_camera_model_update(%s, %s, %L, null, %L, null, null, null, null, null)',
    dup, nik, 'Prueba Q', '35mm'), 'P1115');
  perform pg_temp.yo();
  assert (select name from public.camera_models where id = dup) = 'Prueba V', 'the rename did not happen';

  -- ── Merge with a collision: preview says so, merge refuses ──
  perform pg_temp.como(adm);
  preview := public.admin_camera_model_merge_preview(y, x);
  assert (preview ->> 'cameras')::int = 1 and (preview ->> 'people')::int = 1
     and (preview ->> 'collisions')::int = 1, format('collision preview %s', preview);
  perform pg_temp.espera_error(format('select public.admin_camera_model_merge(%s, %s)', y, x), 'P1115');
  perform pg_temp.yo();
  assert (select camera_model_id from public.cameras where id = cam_ay) = y
     and (select status from public.camera_models where id = y) = 'approved', 'nothing moved';

  -- ── Merge without one, then undo ──
  perform pg_temp.como(adm);
  preview := public.admin_camera_model_merge_preview(z, w);
  assert (preview ->> 'collisions')::int = 0 and (preview ->> 'cameras')::int = 1, 'clean preview';
  change := public.admin_camera_model_merge(z, w);
  perform pg_temp.yo();
  assert (select camera_model_id = w and model = 'Prueba W' from public.cameras where id = cam_bz), 'moved';
  assert (select status = 'merged' and merged_into = w from public.camera_models where id = z), 'merged';
  perform pg_temp.como(adm);
  perform public.admin_camera_model_undo_merge(change);
  perform pg_temp.espera_error(format('select public.admin_camera_model_undo_merge(%s)', change), 'P1114');
  perform pg_temp.yo();
  assert (select camera_model_id = z and model = 'Prueba Z' from public.cameras where id = cam_bz), 'undone';
  assert (select status from public.camera_models where id = z) = 'approved', 'and the model is back';

  -- Approving a proposal whose name exists merges it into the approved one.
  perform pg_temp.como(b);
  dup := public.propose_camera_model(nik, 'Prueba Dup');
  perform pg_temp.yo();
  insert into public.camera_models (manufacturer_id, name, status, source)
  values (nik, 'prueba-dup', 'approved', 'curada') returning id into y;
  perform pg_temp.como(adm);
  perform public.admin_camera_model_review(dup, 'approved');
  perform pg_temp.yo();
  assert (select status = 'merged' and merged_into = y from public.camera_models where id = dup), 'review merges';

  -- ── A deleted camera keeps the name it had ──
  insert into public.cameras (owner_user_id, camera_model_id) values (a, w) returning id into cam_del;
  insert into public.rolls (owner_user_id, code, client_uuid, camera_id)
  values (a, 'R970', gen_random_uuid(), cam_del) returning id into roll1;
  delete from public.cameras where id = cam_del;
  perform pg_temp.como(adm);
  perform public.admin_camera_model_update(w, nik, 'Prueba W Nueva', null, '35mm', null, null, null, null, null);
  perform pg_temp.yo();
  select camera_snapshot ->> 'display_name' into frozen from public.rolls where id = roll1;
  assert frozen = 'Prueba Nikon Prueba W', format('the roll keeps the name at deletion (%s)', frozen);

  -- ── Manufacturers and mounts carry their cameras ──
  perform pg_temp.como(adm);
  perform public.admin_manufacturer_update(nik, 'Prueba Nikon Corp');
  perform public.admin_lens_mount_update(mnt, 'Prueba F Bayoneta');
  perform pg_temp.yo();
  assert (select maker = 'Prueba Nikon Corp' and mount = 'Prueba F Bayoneta'
            from public.cameras where id = cam_ax), 'the camera follows maker and mount';
  perform pg_temp.como(adm);
  change := public.admin_lens_mount_merge(mnt2, mnt);
  perform public.admin_lens_mount_undo_merge(change);
  perform pg_temp.yo();
  assert (select status from public.lens_mounts where id = mnt2) = 'approved', 'mount merge undone';

  -- ── Each form offers its own makers ──
  perform pg_temp.como(a);
  assert not exists (select 1 from public.catalog_manufacturers('film') where id = leica),
    'a maker of cameras only is not a film maker';
  assert exists (select 1 from public.catalog_manufacturers('camera') where id = leica), 'it is a camera maker';
  perform pg_temp.espera_error('select * from public.catalog_manufacturers(''lente'')', 'P1103');
  perform pg_temp.yo();
end $$;
