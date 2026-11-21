-- How cameras meet the catalogue, end to end (20261122090000). Run inside
-- BEGIN / ROLLBACK after film_inventory_helpers.sql. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; adm uuid;
  mk bigint; x bigint; y bigint;
  c1 bigint; c2 bigint; c3 bigint; c4 bigint; c5 bigint; c6 bigint;
  res jsonb; batch uuid;
begin
  a := pg_temp.inv_user('flowa');
  b := pg_temp.inv_user('flowb');
  adm := pg_temp.inv_user('flowadm');
  update public.user_roles set role = 'admin' where user_id = adm;
  insert into public.manufacturers (name, status) values ('Prueba Flujo', 'approved') returning id into mk;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (mk, 'Prueba X', 'SLR', '35mm', 'approved', 'curada') returning id into x;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (mk, 'Prueba Y', 'SLR', '35mm', 'approved', 'curada') returning id into y;

  -- ── Saved by hand, exactly a model: it links itself and is recorded ──
  perform pg_temp.como(a);
  insert into public.cameras (owner_user_id, maker, model) values (a, 'prueba flujo', 'prueba-x') returning id into c1;
  perform pg_temp.yo();
  assert (select camera_model_id = x and maker = 'Prueba Flujo' and model = 'Prueba X' and type = 'SLR'
            from public.cameras where id = c1), 'a camera that is a model links itself';
  assert exists (select 1 from app_private.camera_matches where camera_id = c1 and model_id = x and matched_by is null),
    'the link is recorded';

  -- All in the maker field.
  perform pg_temp.como(b);
  insert into public.cameras (owner_user_id, maker) values (b, 'Prueba Flujo Prueba Y') returning id into c2;
  perform pg_temp.yo();
  assert (select camera_model_id = y and model = 'Prueba Y' from public.cameras where id = c2),
    '«Prueba Flujo Prueba Y» in the maker field is maker + model';

  -- A's second of the same model stays as written; so does a text with no model.
  perform pg_temp.como(a);
  -- (Written the same twice is refused before any of this: one name per
  -- person. Written another way, it is the same model.)
  insert into public.cameras (owner_user_id, maker) values (a, 'Prueba Flujo Prueba X') returning id into c3;
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Flujo', 'La de mi tío') returning id into c4;
  perform pg_temp.yo();
  assert (select camera_model_id is null from public.cameras where id = c3), 'a second of a model waits for January';
  assert (select camera_model_id is null from public.cameras where id = c4), 'what is not a model stays written';

  -- Editing the text into a model links it.
  perform pg_temp.como(a);
  update public.cameras set model = 'Prueba Y' where id = c4;
  perform pg_temp.yo();
  assert (select camera_model_id = y from public.cameras where id = c4), 'an edit into a model links it';

  -- ── The panel: one card per key ──
  perform set_config('app.camera_keep_text', 'on', true);
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Flujo', 'Vieja Rara') returning id into c5;
  insert into public.cameras (owner_user_id, maker, model) values (b, 'prueba flujo', 'vieja  rara') returning id into c6;
  perform set_config('app.camera_keep_text', '', true);
  perform pg_temp.como(adm);
  assert (select cameras = 2 and people = 2 from public.admin_unmatched_cameras()
           where lower(maker) = 'prueba flujo' and lower(model) like 'vieja%rara'),
    'two spellings, one card';
  perform pg_temp.espera_error('select app_private.camera_text_key(''a'', ''b'')', '42501');
  res := public.admin_match_cameras('PRUEBA FLUJO', 'vieja-rara', x);
  perform pg_temp.yo();
  assert (res ->> 'matched')::int = 1 and (res ->> 'skipped')::int = 1, format('one moved, A has an X (%s)', res);
  assert (select camera_model_id = x from public.cameras where id = c6), 'B''s spelling is linked too';

  -- ── Undo keeps the text: it does not link again ──
  perform pg_temp.como(adm);
  perform public.admin_camera_match_undo((res ->> 'batch')::uuid);
  perform pg_temp.yo();
  assert (select camera_model_id is null and model = 'vieja  rara' from public.cameras where id = c6),
    'undone, as written';

  -- ── The record goes with its camera, and with its account ──
  delete from public.cameras where id = c1;
  assert not exists (select 1 from app_private.camera_matches where camera_id = c1), 'a deleted camera takes its record';
  assert exists (select 1 from app_private.camera_matches where owner_user_id = b), 'B has records';
  delete from auth.users where id = b;
  assert not exists (select 1 from app_private.camera_matches where owner_user_id = b), 'a deleted account takes them all';
end $$;
