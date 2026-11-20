-- After a link its card goes; a group can be put away by hand; both undo
-- (20261121210000). Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql
-- and the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; adm uuid;
  mk bigint; x bigint; cam_ax bigint; cam_a bigint; cam_b bigint; cam_b2 bigint;
  res jsonb;
begin
  a := pg_temp.inv_user('chida');
  b := pg_temp.inv_user('chidb');
  adm := pg_temp.inv_user('chidadm');
  update public.user_roles set role = 'admin' where user_id = adm;

  insert into public.manufacturers (name, status) values ('Prueba Oculta', 'approved') returning id into mk;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (mk, 'Prueba X', 'SLR', '35mm', 'approved', 'curada') returning id into x;
  insert into public.cameras (owner_user_id, camera_model_id) values (a, x) returning id into cam_ax;
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Oculta', 'X vieja') returning id into cam_a;
  insert into public.cameras (owner_user_id, maker, model) values (b, 'Prueba Oculta', 'X vieja') returning id into cam_b;

  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.admin_hide_unmatched(%L, %L)', 'Prueba Oculta', 'X vieja'), 'P1205');
  perform pg_temp.espera_error('select count(*) from app_private.camera_match_hidden', '42501');
  perform pg_temp.yo();

  perform pg_temp.como(adm);
  assert (select cameras from public.admin_unmatched_cameras() where maker = 'Prueba Oculta') = 2, 'two cameras wait';

  -- A link: B's moves, A's stays (A has X), and the card goes.
  res := public.admin_match_cameras('Prueba Oculta', 'X vieja', x);
  assert (res ->> 'matched')::int = 1 and (res ->> 'skipped')::int = 1, format('one moved (%s)', res);
  assert not exists (select 1 from public.admin_unmatched_cameras() where maker = 'Prueba Oculta'), 'the card goes';
  perform public.admin_camera_match_undo((res ->> 'batch')::uuid);
  assert (select cameras from public.admin_unmatched_cameras() where maker = 'Prueba Oculta') = 2, 'undo brings both back';

  -- A link that moves nothing keeps the card, to choose another model.
  delete from public.cameras where id = cam_b;
  perform pg_temp.yo();
  delete from public.cameras where id = cam_b;
  perform pg_temp.como(adm);
  res := public.admin_match_cameras('Prueba Oculta', 'X vieja', x);
  assert (res ->> 'matched')::int = 0, 'nothing moved';
  assert (select cameras from public.admin_unmatched_cameras() where maker = 'Prueba Oculta') = 1, 'the card stays';

  -- Put away by hand, and back.
  res := public.admin_hide_unmatched('Prueba Oculta', 'X vieja');
  assert (res ->> 'hidden')::int = 1, 'one put away';
  assert not exists (select 1 from public.admin_unmatched_cameras() where maker = 'Prueba Oculta'), 'gone from the list';
  perform pg_temp.espera_error(format('select public.admin_hide_unmatched(%L, %L)', 'Prueba Oculta', 'X vieja'), 'P1109');
  perform pg_temp.espera_error(format('select public.admin_match_cameras(%L, %L, %s)', 'Prueba Oculta', 'X vieja', x), 'P1109');
  perform pg_temp.yo();

  -- Someone who types the same text later still shows.
  insert into public.cameras (owner_user_id, maker, model) values (b, 'Prueba Oculta', 'X vieja') returning id into cam_b2;
  perform pg_temp.como(adm);
  assert (select cameras from public.admin_unmatched_cameras() where maker = 'Prueba Oculta') = 1, 'a new one shows';
  perform public.admin_camera_match_undo((res ->> 'batch')::uuid);
  assert (select cameras from public.admin_unmatched_cameras() where maker = 'Prueba Oculta') = 2, 'undo puts it back';
  perform pg_temp.yo();
  assert (select camera_model_id is null and model = 'X vieja' from public.cameras where id = cam_a), 'A''s camera never changed';
end $$;
