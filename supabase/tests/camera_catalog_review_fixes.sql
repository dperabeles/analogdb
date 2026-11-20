-- Camera catalog, fixes after the final review (20261121110000): a
-- manufacturer that is someone's proposal never reaches another person's
-- camera, and a camera pointed at a merged model follows it. Run inside
-- BEGIN / ROLLBACK after film_inventory_helpers.sql and after the other camera
-- suites (they count the log). Synthetic accounts only.
do $$
declare
  a uuid; b uuid; adm uuid;
  fujifilm bigint; a_fuji bigint; a_model bigint; cam_b bigint; change bigint;
  nik bigint; z bigint; w bigint; cam bigint; film bigint;
begin
  a := pg_temp.inv_user('crfa');
  b := pg_temp.inv_user('crfb');
  adm := pg_temp.inv_user('crfadm');
  update public.user_roles set role = 'admin' where user_id = adm;
  insert into public.manufacturers (name, status) values ('Prueba Fujifilm', 'approved') returning id into fujifilm;
  insert into public.manufacturers (name, status) values ('Prueba Nikon R', 'approved') returning id into nik;

  -- A proposes a maker and a model under it.
  perform pg_temp.como(a);
  a_fuji := public.propose_manufacturer('Prueba Fuji Secreta');
  a_model := public.propose_camera_model(a_fuji, 'Prueba GW');
  perform pg_temp.yo();

  -- A's maker merges into Fujifilm, the model is approved, B uses it...
  perform pg_temp.como(adm);
  change := public.admin_manufacturer_merge(a_fuji, fujifilm);
  perform public.admin_camera_model_review(a_model, 'approved');
  perform pg_temp.yo();
  insert into public.cameras (owner_user_id, camera_model_id) values (b, a_model) returning id into cam_b;
  assert (select maker from public.cameras where id = cam_b) = 'Prueba Fujifilm', 'B sees the approved maker';
  -- An approved model cannot be moved to its author's unapproved maker.
  perform pg_temp.como(a);
  z := public.propose_manufacturer('Prueba Fuji Segunda');
  perform pg_temp.yo();
  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format(
    'select public.admin_camera_model_update(%s, %s, %L, null, null, null, null, null, null, null)',
    a_model, z, 'Prueba GW'), 'P1103');
  perform pg_temp.yo();
  assert (select maker from public.cameras where id = cam_b) = 'Prueba Fujifilm', 'still the approved one';
  -- ...and undoing the merge would put A's proposal on B's camera: refused.
  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format('select public.admin_manufacturer_undo_merge(%s)', change), 'P1114');
  perform pg_temp.yo();
  assert (select maker from public.cameras where id = cam_b) = 'Prueba Fujifilm', 'B''s camera is untouched';

  -- The same for an approved film moved by the merge.
  perform pg_temp.como(a);
  a_fuji := public.propose_manufacturer('Prueba Fuji Otra');
  film := public.propose_film_stock(a_fuji, 'Prueba Film Fuji', 400, 'COLOR');
  perform pg_temp.yo();
  perform pg_temp.como(adm);
  change := public.admin_manufacturer_merge(a_fuji, fujifilm);
  perform pg_temp.yo();
  update public.film_stocks set status = 'approved', in_catalog = true where id = film;
  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format('select public.admin_manufacturer_undo_merge(%s)', change), 'P1114');
  perform pg_temp.yo();

  -- Even written by hand, a camera never copies another person's
  -- unapproved maker.
  perform pg_temp.como(a);
  a_fuji := public.propose_manufacturer('Prueba Fuji Tercera');
  perform pg_temp.yo();
  insert into public.camera_models (manufacturer_id, name, status, source)
  values (a_fuji, 'Prueba Forzada', 'approved', 'curada') returning id into w;
  perform pg_temp.espera_error(format(
    'insert into public.cameras (owner_user_id, camera_model_id) values (%L, %s)', b, w), 'P1103');

  -- ── A camera pointed at a merged model follows it ──
  insert into public.camera_models (manufacturer_id, name, format, status, source)
  values (nik, 'Prueba Z9', '35mm', 'approved', 'curada') returning id into z;
  insert into public.camera_models (manufacturer_id, name, format, status, source)
  values (nik, 'Prueba W9', '35mm', 'approved', 'curada') returning id into w;
  perform pg_temp.como(adm);
  perform public.admin_camera_model_merge(z, w);
  perform pg_temp.yo();
  perform pg_temp.como(b);
  insert into public.cameras (owner_user_id, camera_model_id) values (b, z) returning id into cam;
  assert (select camera_model_id = w and model = 'Prueba W9' from public.cameras where id = cam),
    'a cached id of a merged model lands on the one it was merged into';
  update public.cameras set camera_model_id = z, show_in_quick_mode = false where id = cam;
  assert (select camera_model_id = w and not show_in_quick_mode from public.cameras where id = cam),
    'and an edit from a stale cache saves';
  perform pg_temp.yo();
end $$;
