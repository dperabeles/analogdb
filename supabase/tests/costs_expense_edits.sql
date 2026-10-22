-- Edit, void and restore any cost record by its id, as the Registros list of
-- Cifras does, also after its roll or gear was deleted (ANA-184).
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid;
  portra bigint; l1 bigint; cam bigint; cam2 bigint;
  r bigint; r2 bigint; rinv bigint;
  res jsonb; cmd uuid := gen_random_uuid();
  fr uuid; lc uuid; eq uuid; eq3 uuid; frinv uuid; pinv uuid; devsc uuid; dev2 uuid;
begin
  a := pg_temp.inv_user('cxa');
  b := pg_temp.inv_user('cxb');
  perform pg_temp.inv_member(a, 'costs');
  perform pg_temp.inv_member(b, 'costs');
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Portra Edit', 400, 'COLOR', false) returning id into portra;
  insert into public.labs (name, status) values ('Lab Costos Edit', 'approved') returning id into l1;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Edit', '35mm') returning id into cam;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Edit Dos', '35mm') returning id into cam2;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, dev_lab_id)
  values (a, 'R921', gen_random_uuid(), portra, 35, 'Developed', l1) returning id into r;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, dev_lab_id)
  values (a, 'R922', gen_random_uuid(), portra, 35, 'Developed', l1) returning id into r2;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R923', gen_random_uuid(), portra, 35, 'Developed') returning id into rinv;

  perform pg_temp.como(a);
  fr := (public.film_cost_set(gen_random_uuid(), r, null, 25000, 'MXN', '2026-03-01') ->> 'id')::uuid;
  lc := (public.lab_costs_save(gen_random_uuid(), r, '[]',
          '[{"kind":"dev","amount_minor":18000,"currency":"MXN","charged_on":"2026-05-02"}]') -> 'charges' -> 0 ->> 'id')::uuid;
  eq := (public.equipment_cost_set(gen_random_uuid(), 'camera', cam, null, 350000, 'MXN', '2026-04-04') ->> 'id')::uuid;

  -- Correct each kind of record; the version goes up.
  res := public.expense_update(cmd, 'film_roll', fr, 1, 26000, 'USD', '2026-03-05');
  assert res = jsonb_build_object('id', fr, 'version', 2, 'active', true), 'film corrected';
  assert public.expense_update(cmd, 'film_roll', fr, 1, 26000, 'USD', '2026-03-05') = res, 'replay';
  res := public.expense_update(gen_random_uuid(), 'lab', lc, 1, 19000, 'MXN', '2026-05-03');
  assert (res ->> 'version')::int = 2, 'lab corrected';
  res := public.expense_update(gen_random_uuid(), 'equipment', eq, 1, 340000, 'MXN', null);
  assert (res ->> 'version')::int = 2, 'equipment corrected';
  perform pg_temp.yo();
  assert (select (unit_price_minor, currency::text, purchased_on) from public.film_purchases where id = fr)
       = (26000::bigint, 'USD'::text, date '2026-03-05'), 'film values';
  assert (select (amount_minor, charged_on) from public.lab_charges where id = lc)
       = (19000::bigint, date '2026-05-03'), 'lab values';
  assert (select amount_minor = 340000 and purchased_on is null from public.equipment_purchases where id = eq), 'equipment values';

  -- What each kind cannot be corrected to.
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 2, null, null, %L)',
    'lab', lc, '2026-05-03'), 'P1103');
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 2, null, null, null)',
    'equipment', eq), 'P1103');
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 2, null, null, null)',
    'film_roll', fr), 'P1103');
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 2, 1, %L, null)',
    'film', fr, 'MXN'), 'P1103');
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 1, 1, %L, null)',
    'lab', lc, 'MXN'), 'P1105');

  -- Void and restore each kind.
  res := public.expense_void(gen_random_uuid(), 'film_roll', fr, 2);
  assert res = jsonb_build_object('id', fr, 'version', 3, 'active', false), 'film voided';
  assert not exists (select 1 from public.roll_film_origin where roll_id = r), 'voided film does not count';
  perform pg_temp.espera_error(format('select public.expense_void(gen_random_uuid(), %L, %L, 3)', 'film_roll', fr), 'P1103');
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 3, 1, %L, null)',
    'film_roll', fr, 'MXN'), 'P1103');
  res := public.expense_restore(gen_random_uuid(), 'film_roll', fr, 3);
  assert res = jsonb_build_object('id', fr, 'version', 4, 'active', true), 'film restored';
  assert (select unit_price_minor from public.roll_film_origin where roll_id = r) = 26000, 'restored film counts again';
  perform pg_temp.espera_error(format('select public.expense_restore(gen_random_uuid(), %L, %L, 4)', 'film_roll', fr), 'P1103');
  res := public.expense_void(gen_random_uuid(), 'lab', lc, 2);
  res := public.expense_restore(gen_random_uuid(), 'lab', lc, 3);
  assert (res ->> 'version')::int = 4 and (res ->> 'active')::boolean, 'lab restored';
  res := public.expense_void(gen_random_uuid(), 'equipment', eq, 2);
  res := public.expense_restore(gen_random_uuid(), 'equipment', eq, 3);
  assert (res ->> 'version')::int = 4 and (res ->> 'active')::boolean, 'equipment restored';

  -- Restoring when another active record already took its place.
  perform public.expense_void(gen_random_uuid(), 'lab', lc, 4);
  perform public.lab_costs_save(gen_random_uuid(), r, '[]', '[{"kind":"dev","amount_minor":1,"currency":"MXN"}]');
  perform pg_temp.espera_error(format('select public.expense_restore(gen_random_uuid(), %L, %L, 5)', 'lab', lc), 'P1111');
  res := public.lab_costs_save(gen_random_uuid(), r2, '[]', '[{"kind":"dev_scan","amount_minor":30000,"currency":"MXN"}]');
  devsc := (res -> 'charges' -> 0 ->> 'id')::uuid;
  res := public.lab_costs_save(gen_random_uuid(), r2, res -> 'charges', '[{"kind":"dev","amount_minor":20000,"currency":"MXN"}]');
  dev2 := (res -> 'charges' -> 0 ->> 'id')::uuid;
  perform pg_temp.espera_error(format('select public.expense_restore(gen_random_uuid(), %L, %L, 2)', 'lab', devsc), 'P1111');
  perform public.expense_void(gen_random_uuid(), 'film_roll', fr, 4);
  perform public.film_cost_set(gen_random_uuid(), r, null, 1000, 'MXN', null);
  perform pg_temp.espera_error(format('select public.expense_restore(gen_random_uuid(), %L, %L, 5)', 'film_roll', fr), 'P1111');
  perform public.expense_void(gen_random_uuid(), 'equipment', eq, 4);
  perform public.equipment_cost_set(gen_random_uuid(), 'camera', cam, null, 1, 'MXN', null);
  perform pg_temp.espera_error(format('select public.expense_restore(gen_random_uuid(), %L, %L, 5)', 'equipment', eq), 'P1111');
  frinv := (public.film_cost_set(gen_random_uuid(), rinv, null, 5000, 'MXN', null) ->> 'id')::uuid;
  perform public.expense_void(gen_random_uuid(), 'film_roll', frinv, 1);
  perform pg_temp.yo();
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency)
  values (a, portra, 35, 1, 18000, 'MXN') returning id into pinv;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, status, roll_id, loaded_on)
  values (a, pinv, portra, 35, 'loaded', rinv, current_date);
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.expense_restore(gen_random_uuid(), %L, %L, 2)', 'film_roll', frinv), 'P1111');
  assert (select voided_at is not null from public.film_purchases where id = frinv), 'restore conflicts change nothing';

  -- Inventory purchases are not edited this way.
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 1, 1, %L, null)',
    'film_roll', pinv, 'MXN'), 'P1109');
  perform pg_temp.espera_error(format('select public.expense_void(gen_random_uuid(), %L, %L, 1)', 'film_roll', pinv), 'P1109');

  -- After the roll or the camera is deleted, the records stay editable.
  delete from public.rolls where id = r2;
  eq3 := (public.equipment_cost_set(gen_random_uuid(), 'camera', cam2, null, 90000, 'MXN', null) ->> 'id')::uuid;
  delete from public.cameras where id = cam2;
  res := public.expense_update(gen_random_uuid(), 'lab', dev2, 1, 21000, 'MXN', '2026-07-01');
  res := public.expense_void(gen_random_uuid(), 'lab', dev2, 2);
  res := public.expense_restore(gen_random_uuid(), 'lab', dev2, 3);
  assert (res ->> 'active')::boolean, 'undo after the roll was deleted';
  res := public.expense_update(gen_random_uuid(), 'equipment', eq3, 1, 95000, 'MXN', null);
  res := public.expense_void(gen_random_uuid(), 'equipment', eq3, 2);
  res := public.expense_restore(gen_random_uuid(), 'equipment', eq3, 3);
  assert (res ->> 'active')::boolean, 'undo after the camera was deleted';
  perform pg_temp.yo();
  assert (select roll_id is null and amount_minor = 21000 and voided_at is null from public.lab_charges where id = dev2),
         'deleted roll charge corrected and restored';
  assert (select camera_id is null and label = 'Prueba Cost Cam Edit Dos' and amount_minor = 95000
          from public.equipment_purchases where id = eq3), 'deleted camera purchase corrected and restored';

  -- Other accounts never reach these records.
  perform pg_temp.como(b);
  perform pg_temp.espera_error(format('select public.expense_void(gen_random_uuid(), %L, %L, 4)', 'lab', dev2), 'P1109');
  perform pg_temp.espera_error(format('select public.expense_update(gen_random_uuid(), %L, %L, 4, 1, %L, null)',
    'equipment', eq3, 'MXN'), 'P1109');
  perform pg_temp.espera_error(format('select public.expense_restore(gen_random_uuid(), %L, %L, 5)', 'film_roll', fr), 'P1109');
  perform pg_temp.yo();
  assert (select voided_at is null from public.lab_charges where id = dev2), 'B changed nothing';
end $$;
