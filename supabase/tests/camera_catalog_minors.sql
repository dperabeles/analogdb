-- Camera catalog, small fixes (20261121170000): an older app does not reset
-- a camera's frame, a mount merged meanwhile still proposes, and a
-- manufacturer merge says beforehand who would end with two equal cameras.
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql. Synthetic
-- accounts only.
do $$
declare
  a uuid; adm uuid;
  mk bigint; x bigint; y bigint; m1 bigint; m2 bigint; lf bigint; cam bigint; prop bigint; mq bigint;
  preview jsonb;
begin
  a := pg_temp.inv_user('cmina');
  adm := pg_temp.inv_user('cminadm');
  update public.user_roles set role = 'admin' where user_id = adm;
  insert into public.manufacturers (name, status) values ('Prueba Diez', 'approved') returning id into mk;
  insert into public.lens_mounts (name) values ('Prueba Tablero') returning id into m1;
  insert into public.lens_mounts (name) values ('Prueba Tablero Dos') returning id into m2;
  insert into public.camera_models (manufacturer_id, name, type, format, frame_sizes, mount_id, status, source)
  values (mk, 'Prueba LF', 'Vista / Gran formato', 'Large Format', '{4x5,5x7}', m1, 'approved', 'curada')
  returning id into lf;

  -- An older app sends no frame outside 120: the camera keeps its own.
  insert into public.cameras (owner_user_id, camera_model_id, frame_size) values (a, lf, '5x7') returning id into cam;
  update public.cameras set frame_size = null, model = 'Prueba LF', show_in_quick_mode = false where id = cam;
  assert (select frame_size from public.cameras where id = cam) = '5x7', 'the frame stays';
  update public.cameras set frame_size = '4x5' where id = cam;
  assert (select frame_size from public.cameras where id = cam) = '4x5', 'and a new app still changes it';

  -- A mount merged after the app cached it: the proposal takes its target.
  perform pg_temp.como(adm);
  perform public.admin_lens_mount_merge(m2, m1);
  perform pg_temp.yo();
  perform pg_temp.como(a);
  prop := public.propose_camera_model(mk, 'Prueba Propuesta', 'SLR', '35mm', null, m2);
  assert (select mount_id from public.camera_models where id = prop) = m1, 'the merged mount becomes its target';
  perform pg_temp.yo();

  -- A manufacturer merge says beforehand who would end with two equal
  -- cameras, and how much moves.
  insert into public.manufacturers (name, status) values ('Prueba Equis', 'approved') returning id into x;
  insert into public.manufacturers (name, status) values ('Prueba Ye', 'approved') returning id into y;
  insert into public.camera_models (manufacturer_id, name, format, status, source)
  values (x, 'Q', '35mm', 'approved', 'curada') returning id into mq;
  insert into public.cameras (owner_user_id, camera_model_id) values (a, mq);
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Ye', 'Q');
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.admin_manufacturer_merge_preview(%s, %s)', x, y), 'P1205');
  perform pg_temp.yo();
  perform pg_temp.como(adm);
  preview := public.admin_manufacturer_merge_preview(x, y);
  perform pg_temp.yo();
  assert (preview ->> 'camera_models')::int = 1 and (preview ->> 'cameras')::int = 1
     and (preview ->> 'collisions')::int = 1, format('maker merge preview %s', preview);
end $$;
