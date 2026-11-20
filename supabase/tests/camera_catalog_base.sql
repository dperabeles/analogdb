-- Camera catalog base (20261121090000): vocabulary, lens mounts, camera
-- models, and a user's camera that follows its model. Run inside BEGIN /
-- ROLLBACK after film_inventory_helpers.sql. Synthetic accounts only.
do $$
declare
  a uuid; b uuid;
  canon bigint; kmz bigint; fd bigint; m120 bigint;
  ae1 bigint; mamiya bigint; zenit bigint; a_own bigint;
  cam bigint; cam2 bigint; cam3 bigint;
  r public.cameras;
begin
  -- ── Vocabulary: one list on the server, the same the app writes ──
  assert app_private.camera_format_ok('220'), '220 is a format';
  assert not app_private.camera_format_ok('35 mm'), 'a spelling the app never writes is not';
  assert app_private.camera_format_ok(null), 'unknown is allowed';
  assert app_private.camera_type_ok('Rangefinder') and app_private.camera_type_ok('Otro'), 'types';
  assert not app_private.camera_type_ok('rangefinder'), 'types are exact';
  assert app_private.camera_frame_ok('Large Format', '4x5'), 'sheet sizes';
  assert app_private.camera_frame_ok('220', '6x7'), 'roll sizes on 220';
  assert not app_private.camera_frame_ok('35mm', '6x6'), 'no frame on 35mm';
  assert app_private.camera_frame_ok('35mm', null), 'null frame anywhere';
  assert app_private.camera_model_key('AE-1 Program') = app_private.camera_model_key('ae1 program'),
    'spelling does not make another model';

  a := pg_temp.inv_user('cama');
  b := pg_temp.inv_user('camb');

  -- Catalog rows as a migration writes them.
  insert into public.manufacturers (name, status) values ('Prueba Canon', 'approved') returning id into canon;
  insert into public.manufacturers (name, status) values ('KMZ', 'approved') returning id into kmz;
  insert into public.lens_mounts (name, status) values ('Prueba FD', 'approved') returning id into fd;
  insert into public.camera_models (manufacturer_id, name, type, format, mount_id, interchangeable,
                                    year_from, status, source, source_ref)
  values (canon, 'AE-1 Prueba', 'SLR', '35mm', fd, true, 1981, 'approved', 'curada', null)
  returning id into ae1;
  insert into public.camera_models (manufacturer_id, name, type, format, frame_sizes, status, source)
  values (canon, 'Prueba 645', 'SLR', '120', array['6x4.5', '6x6'], 'approved', 'curada')
  returning id into mamiya;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (kmz, 'Zenit Prueba', 'SLR', '35mm', 'approved', 'curada') returning id into zenit;
  insert into public.camera_models (manufacturer_id, name, format, status, created_by)
  values (canon, 'Secreta de A', '35mm', 'pending', a) returning id into a_own;

  perform pg_temp.espera_error(format(
    'insert into public.camera_models (manufacturer_id, name, status) values (%s, %L, %L)',
    canon, 'ae1 prueba', 'approved'), '23505');
  perform pg_temp.espera_error(format(
    'insert into public.camera_models (manufacturer_id, name, format, frame_sizes, status) values (%s, %L, %L, %L, %L)',
    canon, 'Mala', '35mm', '{6x6}', 'approved'), '23514');

  -- ── Isolation ──
  perform pg_temp.como(a);
  assert exists (select 1 from public.camera_models where id = ae1), 'A reads the catalog';
  assert exists (select 1 from public.camera_models where id = a_own), 'A reads her own proposal';
  assert exists (select 1 from public.lens_mounts where id = fd), 'A reads the mounts';
  perform pg_temp.yo();
  perform pg_temp.como(b);
  assert not exists (select 1 from public.camera_models where id = a_own), 'B never sees A''s proposal';
  perform pg_temp.espera_error(format(
    'insert into public.camera_models (manufacturer_id, name) values (%s, %L)', canon, 'Hack'), '42501');
  perform pg_temp.espera_error('insert into public.lens_mounts (name) values (''Hack'')', '42501');
  perform pg_temp.espera_error(format(
    'update public.camera_models set name = %L where id = %s', 'Hack', ae1), '42501');
  -- Pointing a camera at A's proposal reveals nothing: same error as no model.
  perform pg_temp.espera_error(format(
    'insert into public.cameras (owner_user_id, camera_model_id) values (%L, %s)', b, a_own), 'P1103');
  perform pg_temp.espera_error(format(
    'insert into public.cameras (owner_user_id, camera_model_id) values (%L, %s)', b, -1), 'P1103');
  perform pg_temp.yo();

  -- ── A camera follows its model ──
  perform pg_temp.como(a);
  insert into public.cameras (owner_user_id, maker, model, format, camera_model_id)
  values (a, 'otra cosa', 'lo que sea', '120', ae1) returning id into cam;
  select * into r from public.cameras where id = cam;
  assert r.maker = 'Prueba Canon' and r.model = 'AE-1 Prueba', 'the catalog name, not what was typed';
  assert r.format = '35mm' and r.type = 'SLR' and r.mount = 'Prueba FD'
     and r.supports_interchangeable_lenses and r.frame_size is null, 'and its data';

  insert into public.cameras (owner_user_id, camera_model_id, frame_size)
  values (a, mamiya, '6x6') returning id into cam2;
  assert (select frame_size from public.cameras where id = cam2) = '6x6', 'a frame the model allows stays';
  update public.cameras set frame_size = '6x9' where id = cam2;
  assert (select frame_size from public.cameras where id = cam2) = '6x4.5',
    'one it does not allow becomes the model''s first';

  -- An older app rewrites the text: the model wins, the rest is kept.
  update public.cameras set model = 'AE1', maker = 'canon', show_in_quick_mode = false where id = cam;
  select * into r from public.cameras where id = cam;
  assert r.model = 'AE-1 Prueba' and r.maker = 'Prueba Canon', 'the model''s name comes back';
  assert not r.show_in_quick_mode, 'and Quick Add is saved';

  -- The canonical name is kept as written.
  insert into public.cameras (owner_user_id, camera_model_id) values (a, zenit) returning id into cam3;
  assert (select maker from public.cameras where id = cam3) = 'KMZ', 'KMZ stays KMZ';

  -- Her own proposal is hers to use.
  update public.cameras set camera_model_id = a_own where id = cam3;
  assert (select model from public.cameras where id = cam3) = 'Secreta de A', 'A uses her proposal';

  -- ── A camera without a model is as today ──
  insert into public.cameras (owner_user_id, maker, model, format, frame_size)
  values (a, 'kmz', 'Libre', '35mm', '6x6') returning id into cam;
  select * into r from public.cameras where id = cam;
  assert r.maker = public.normalize_gear_maker('kmz'), 'free text is normalized as today';
  assert r.frame_size is null, 'and a 35mm camera has no frame';
  insert into public.cameras (owner_user_id, maker, model, format)
  values (a, 'Libre', 'Medio', '6x7') returning id into cam;
  select * into r from public.cameras where id = cam;
  assert r.format = '120' and r.frame_size = '6x7', 'a frame typed as format still means 120';
  perform pg_temp.yo();

  assert (select count(*) from public.catalog_changes where entity in ('camera_model', 'lens_mount')) = 0,
    'nothing logged yet';
  insert into public.catalog_changes (entity, entity_id, action) values ('camera_model', ae1, 'edit');
  insert into public.catalog_changes (entity, entity_id, action) values ('lens_mount', fd, 'edit');
end $$;
