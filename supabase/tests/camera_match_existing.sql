-- The cameras people already had meet the catalogue (20261121190000). Run
-- inside BEGIN / ROLLBACK after film_inventory_helpers.sql, after the
-- migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; adm uuid;
  nik bigint; x bigint; y bigint;
  cam1 bigint; cam2 bigint; cam3 bigint; cam4 bigint; cam5 bigint;
  res jsonb; n integer;
begin
  -- Nothing that is a catalogue model by key stays without one, unless it
  -- would be the person's second of that model.
  assert not exists (
    select 1 from public.cameras c
     where c.camera_model_id is null
       and app_private.camera_text_model(c.maker, c.model) is not null
       and not exists (select 1 from public.cameras o
                        where o.owner_user_id = c.owner_user_id
                          and o.camera_model_id = app_private.camera_text_model(c.maker, c.model))),
    'every camera that is a model by key is linked';
  assert (select count(*) from app_private.camera_matches m
           where m.undone_at is null
             and not exists (select 1 from public.cameras c where c.id = m.camera_id and c.camera_model_id = m.model_id)) = 0,
    'each link kept points at its camera';

  a := pg_temp.inv_user('cmata');
  b := pg_temp.inv_user('cmatb');
  adm := pg_temp.inv_user('cmatadm');
  update public.user_roles set role = 'admin' where user_id = adm;

  insert into public.manufacturers (name, status) values ('Prueba Nikon', 'approved') returning id into nik;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (nik, 'Prueba X', 'SLR', '35mm', 'approved', 'curada') returning id into x;
  insert into public.camera_models (manufacturer_id, name, type, format, status, source)
  values (nik, 'Prueba Y', 'Rangefinder', '35mm', 'approved', 'curada') returning id into y;

  insert into public.cameras (owner_user_id, maker, model, type) values (a, 'Prueba Nikon', 'prueba-x', 'Otro') returning id into cam1;
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Prueba Nikon', 'Prueba Nikon Prueba Y') returning id into cam2;
  insert into public.cameras (owner_user_id, maker, model) values (b, 'Prueba Nikon', 'Prueba X') returning id into cam3;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Nikon', 'Prueba Y de mi papá', '120') returning id into cam4;
  insert into public.cameras (owner_user_id, maker, model, format) values (b, 'Prueba Nikon', 'Prueba Y de mi papá', '120') returning id into cam5;

  -- ── By key ──
  assert app_private.camera_text_model('Prueba Nikon', 'prueba-x') = x, 'another spelling is the model';
  assert app_private.camera_text_model('prueba nikon', 'Prueba Nikon Prueba Y') = y, 'the maker in front is the model';
  assert app_private.camera_text_model('Prueba Nikon', 'Prueba Y de mi papá') is null, 'a longer text is not';
  assert app_private.camera_text_suggestion('Prueba Nikon', 'Prueba Y de mi papá') = y, 'but it is offered first';
  assert app_private.camera_text_model('Otra Marca', 'Prueba X') is null, 'another maker is not';

  assert app_private.match_cameras_by_key() = 3, 'three linked by key';
  assert (select camera_model_id = x and model = 'Prueba X' and type = 'SLR' from public.cameras where id = cam1),
    'the camera follows its model';
  assert (select camera_model_id = y and model = 'Prueba Y' from public.cameras where id = cam2), 'maker in front';
  assert (select camera_model_id = x from public.cameras where id = cam3), 'another person, the same model';
  assert (select camera_model_id is null from public.cameras where id = cam4), 'a longer text waits';

  -- ── The panel: admin only, and never whose ──
  perform pg_temp.como(a);
  perform pg_temp.espera_error('select * from public.admin_unmatched_cameras()', 'P1205');
  perform pg_temp.espera_error(format('select public.admin_match_cameras(%L, %L, %s)', 'Prueba Nikon', 'Prueba Y de mi papá', y), 'P1205');
  perform pg_temp.espera_error('select public.admin_camera_match_undo(gen_random_uuid())', 'P1205');
  perform pg_temp.espera_error('select count(*) from app_private.camera_matches', '42501');
  perform pg_temp.yo();
  perform pg_temp.como(null);
  perform pg_temp.espera_error('select * from public.admin_unmatched_cameras()', '42501');
  perform pg_temp.yo();

  perform pg_temp.como(adm);
  assert (select cameras = 2 and people = 2 and suggestion_id = y
            from public.admin_unmatched_cameras()
           where maker = 'Prueba Nikon' and model = 'Prueba Y de mi papá'), 'one row for the same text, with how many';
  perform pg_temp.espera_error(format('select public.admin_match_cameras(%L, %L, %s)', 'Prueba Nikon', 'Nada así', y), 'P1109');
  perform pg_temp.espera_error(format('select public.admin_match_cameras(%L, %L, %s)', 'Prueba Nikon', 'Prueba Y de mi papá', -1), 'P1103');

  -- A already has a Prueba Y: only B's is linked.
  res := public.admin_match_cameras('Prueba Nikon', 'Prueba Y de mi papá', y);
  assert (res ->> 'matched')::int = 1 and (res ->> 'skipped')::int = 1, format('one linked, one left (%s)', res);
  -- Even the admin's own session never reads other people's cameras.
  assert not exists (select 1 from public.cameras where id in (cam4, cam5)), 'the admin does not see them';
  perform pg_temp.yo();
  assert (select camera_model_id = y and model = 'Prueba Y' and format = '35mm' from public.cameras where id = cam5),
    'B''s follows the model';
  assert (select camera_model_id is null and model = 'Prueba Y de mi papá' from public.cameras where id = cam4), 'A''s stays';

  -- Undo puts back what it was.
  perform pg_temp.como(adm);
  n := public.admin_camera_match_undo((res ->> 'batch')::uuid);
  assert n = 1, 'one put back';
  assert public.admin_camera_match_undo((res ->> 'batch')::uuid) = 0, 'twice does nothing';
  perform pg_temp.yo();
  assert (select camera_model_id is null and model = 'Prueba Y de mi papá' and format = '120' from public.cameras where id = cam5),
    'B''s camera is as it was';

  -- B sees only B's cameras, linked or not.
  perform pg_temp.como(b);
  assert (select count(*) from public.cameras) = 2, 'B sees B''s two cameras';
  assert not exists (select 1 from public.cameras where owner_user_id <> b), 'and nobody else''s';
  perform pg_temp.yo();
end $$;
