-- Camera and lens purchases (ANA-184).
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid;
  cam bigint; zl bigint; camb bigint; cam2 bigint; cam3 bigint;
  res jsonb; cmd uuid := gen_random_uuid();
  pc uuid; pc2 uuid; pz uuid;
  archived bigint;
begin
  a := pg_temp.inv_user('cea');
  b := pg_temp.inv_user('ceb');
  perform pg_temp.inv_member(a, 'costs');
  perform pg_temp.inv_member(b, 'costs');
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Uno', '35mm') returning id into cam;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Dos', '35mm') returning id into cam2;
  insert into public.lenses (owner_user_id, maker, model, mount) values (a, 'Prueba Cost', 'Lente Uno', 'M') returning id into zl;
  insert into public.cameras (owner_user_id, maker, model, format) values (b, 'Prueba Cost', 'Cam B', '35mm') returning id into camb;

  -- Create, replay, correct with the version.
  perform pg_temp.como(a);
  res := public.equipment_cost_set(cmd, 'camera', cam, null, 350000, 'MXN', '2026-04-04');
  assert (res ->> 'active')::boolean and (res ->> 'version')::int = 1, 'camera purchase created';
  pc := (res ->> 'id')::uuid;
  assert public.equipment_cost_set(cmd, 'camera', cam, null, 350000, 'MXN', '2026-04-04') = res, 'replay';
  res := public.equipment_cost_set(gen_random_uuid(), 'camera', cam, 1, 360000, 'MXN', '2026-04-04');
  assert (res ->> 'version')::int = 2 and (res ->> 'id')::uuid = pc, 'corrected in place';
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, 1, 1, %L, null)',
    'camera', cam, 'MXN'), 'P1105');
  -- One active purchase per piece: a second one without the version conflicts.
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, null, 1, %L, null)',
    'camera', cam, 'MXN'), 'P1105');

  -- Clearing amount and date voids it.
  res := public.equipment_cost_set(gen_random_uuid(), 'camera', cam, 2, null, null, null);
  assert not (res ->> 'active')::boolean and (res ->> 'id')::uuid = pc and (res ->> 'version')::int = 3, 'voided';

  -- A purchase can be known by its date only.
  res := public.equipment_cost_set(gen_random_uuid(), 'lens', zl, null, null, null, '2026-04-04');
  pz := (res ->> 'id')::uuid;
  assert (res ->> 'active')::boolean, 'date only is a purchase';
  perform pg_temp.yo();
  assert (select amount_minor is null and currency is null and kind = 'lens' and camera_id is null
          from public.equipment_purchases where id = pz), 'lens purchase without amount';
  assert (select count(*) from public.equipment_purchases where camera_id = cam) = 1, 'replay and correction add nothing';

  -- Invalid input and other accounts' gear change nothing.
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, null, 1, %L, null)',
    'flash', cam2, 'MXN'), 'P1103');
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, null, 1, null, null)',
    'camera', cam2), 'P1103');
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, null, null, null, current_date + 2)',
    'camera', cam2), 'P1103');
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, null, 1, %L, null)',
    'camera', camb, 'MXN'), 'P1109');
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, null, 1, %L, null)',
    'lens', -1, 'MXN'), 'P1109');
  perform pg_temp.yo();
  assert not exists (select 1 from public.equipment_purchases where camera_id in (cam2, camb)), 'nothing written';

  -- Deleting the gear the usual way keeps the purchase with its name.
  perform pg_temp.como(a);
  res := public.equipment_cost_set(gen_random_uuid(), 'camera', cam, null, 350000, 'MXN', '2026-04-04');
  pc2 := (res ->> 'id')::uuid;
  assert (res ->> 'version')::int = 4, 'new purchase continues the camera versions';
  perform pg_temp.espera_error(format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, 1, 1, %L, null)',
    'camera', cam, 'MXN'), 'P1105');
  delete from public.cameras where id = cam;
  delete from public.lenses where id = zl;
  perform pg_temp.yo();
  assert (select camera_id is null and label = 'Prueba Cost Cam Uno' and voided_at is null
          from public.equipment_purchases where id = pc2), 'camera purchase keeps its name';
  assert (select lens_id is null and label = 'Prueba Cost Lente Uno' and voided_at is null
          from public.equipment_purchases where id = pz), 'lens purchase keeps its name';
  assert (select version from public.equipment_purchases where id = pc2) = 5
     and (select version from public.equipment_purchases where id = pz) = 2, 'freezing bumps the version';

  -- Gear without purchases works as before.
  perform pg_temp.como(a);
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Tres', '35mm') returning id into cam3;
  update public.cameras set model = 'Cam Tres B' where id = cam3;
  delete from public.cameras where id = cam3;
  perform pg_temp.yo();
  assert not exists (select 1 from public.cameras where id = cam3), 'plain camera deleted';

  -- Last: deleting the account leaves no purchases and archives nothing new.
  select count(*) into archived from public.deleted_rows where dueno = a;
  perform pg_temp.como(a);
  perform public.delete_my_account();
  perform pg_temp.yo();
  assert not exists (select 1 from public.equipment_purchases where owner_user_id = a), 'purchases gone';
  assert (select count(*) from public.deleted_rows where dueno = a) = archived, 'no new archived copies';
  assert not exists (select 1 from public.deleted_rows where dueno = a and tabla = 'equipment_purchases'),
         'no archived purchases';
end $$;
