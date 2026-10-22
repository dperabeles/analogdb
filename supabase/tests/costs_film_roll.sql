-- Film price of rolls that did not come from the inventory (ANA-184).
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; c uuid;
  portra bigint; gold bigint;
  r bigint; r0 bigint; ru bigint; rn bigint; rb bigint;
  pu uuid; pid uuid; pid2 uuid;
  res jsonb; res2 jsonb;
  archived bigint;
  cmd1 uuid := gen_random_uuid();
begin
  a := pg_temp.inv_user('cfa');
  b := pg_temp.inv_user('cfb');
  c := pg_temp.inv_user('cfc');
  perform pg_temp.inv_member(a, 'costs');
  perform pg_temp.inv_member(a);
  perform pg_temp.inv_member(b, 'costs');
  perform pg_temp.inv_member(c);
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Portra Cost', 400, 'COLOR', false) returning id into portra;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Gold Cost', 200, 'COLOR', false) returning id into gold;

  -- Rolls created the usual way, by direct insert.
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R901', gen_random_uuid(), portra, 35, 'Developed') returning id into r;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R902', gen_random_uuid(), null, null, 'Archived') returning id into r0;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (b, 'R903', gen_random_uuid(), portra, 35, 'Developed') returning id into rb;

  -- Writing costs needs the costs feature; film_inventory alone is not enough.
  perform pg_temp.como(c);
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, null, 100, %L, null)', r, 'MXN'), 'P1102');
  perform pg_temp.yo();

  -- Create, and replay the same command.
  perform pg_temp.como(a);
  res := public.film_cost_set(cmd1, r, null, 25000, 'MXN', '2026-03-01');
  assert (res ->> 'active')::boolean and (res ->> 'version')::int = 1, 'created active, version 1';
  pid := (res ->> 'id')::uuid;
  assert (select origin from public.roll_film_origin where roll_id = r) = 'roll', 'origin roll';
  assert (select unit_price_minor from public.roll_film_origin where roll_id = r) = 25000, 'price on the roll';
  assert (select purchase_version from public.roll_film_origin where roll_id = r) = 1, 'version visible';
  res2 := public.film_cost_set(cmd1, r, null, 25000, 'MXN', '2026-03-01');
  assert res2 = res, 'replay returns the same receipt';
  perform pg_temp.yo();
  assert (select count(*) from public.film_purchases where roll_id = r) = 1, 'replay adds nothing';
  assert (select origin || quantity || film_stock_id || format from public.film_purchases where id = pid)
       = 'roll1' || portra || '35', 'one unit of the roll film';
  assert not exists (select 1 from public.film_units where purchase_id = pid), 'no stock created';

  -- Correct with the version; a stale or missing version conflicts.
  perform pg_temp.como(a);
  res := public.film_cost_set(gen_random_uuid(), r, 1, 26000, 'MXN', '2026-03-02');
  assert (res ->> 'version')::int = 2 and (res ->> 'id')::uuid = pid, 'corrected in place';
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, 1, 27000, %L, null)', r, 'MXN'), 'P1105');
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, null, 27000, %L, null)', r, 'MXN'), 'P1105');

  -- Clearing price and date voids it; a new price is a new purchase.
  res := public.film_cost_set(gen_random_uuid(), r, 2, null, null, null);
  assert not (res ->> 'active')::boolean and (res ->> 'id')::uuid = pid, 'voided, id kept for undo';
  assert (res ->> 'version')::int = 3, 'void bumps the version';
  assert not exists (select 1 from public.roll_film_origin where roll_id = r), 'no film origin after void';
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, 3, 100, %L, null)', r, 'MXN'), 'P1105');
  res := public.film_cost_set(gen_random_uuid(), r, null, 24000, 'MXN', null);
  pid2 := (res ->> 'id')::uuid;
  assert pid2 <> pid and (res ->> 'version')::int = 4, 'new purchase continues the roll versions';
  -- A device that still holds version 1 of the first purchase cannot
  -- overwrite the new one.
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, 1, 1, %L, null)', r, 'MXN'), 'P1105');
  -- Nothing to clear: no-op.
  res := public.film_cost_set(gen_random_uuid(), r0, null, null, null, null);
  assert res = '{"id": null, "version": null, "active": false}'::jsonb, 'clearing nothing is a no-op';
  perform pg_temp.yo();
  assert (select voided_at is not null from public.film_purchases where id = pid), 'old one stays voided';

  -- The expense follows the roll's film while the roll exists.
  update public.rolls set film_stock_id = gold where id = r;
  assert (select film_stock_id from public.roll_film_origin where roll_id = r) = gold, 'follows film change';
  update public.rolls set film_stock_id = null where id = r;
  assert exists (select 1 from public.roll_film_origin where roll_id = r and film_stock_id is null),
         'clearing the film keeps the expense';
  update public.rolls set film_stock_id = gold where id = r;

  -- A roll without film can be priced.
  perform pg_temp.como(a);
  res := public.film_cost_set(gen_random_uuid(), r0, null, 9000, 'MXN', null);
  assert (res ->> 'active')::boolean, 'priced without film';
  perform pg_temp.yo();
  assert (select film_stock_id is null and format is null from public.film_purchases where roll_id = r0),
         'no film, no format';

  -- Deleting the roll the usual way (with more than 5 frames) freezes the film.
  insert into public.roll_exposures (roll_id, frame_number) select r, n from generate_series(1, 8) n;
  perform pg_temp.como(a);
  delete from public.rolls where id = r;
  perform pg_temp.yo();
  assert not exists (select 1 from public.rolls where id = r), 'roll deleted';
  assert (select roll_id is null and film_stock_id = gold and format = 35 and voided_at is null
          from public.film_purchases where id = pid2), 'frozen with the film it had, still active';

  -- Rolls loaded from the inventory, with and without purchase, are managed there.
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency)
  values (a, portra, 35, 1, 18000, 'MXN') returning id into pu;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R904', gen_random_uuid(), portra, 35, 'In Camera') returning id into ru;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, status, roll_id, loaded_on)
  values (a, pu, portra, 35, 'loaded', ru, current_date);
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R905', gen_random_uuid(), portra, 35, 'In Camera') returning id into rn;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, status, roll_id, loaded_on)
  values (a, null, portra, 35, 'loaded', rn, current_date);
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, null, 100, %L, null)', ru, 'MXN'), 'P1110');
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, null, 100, %L, null)', rn, 'MXN'), 'P1110');
  assert (select origin from public.roll_film_origin where roll_id = ru) = 'inventory', 'inventory origin';

  -- The inventory neither lists nor edits roll purchases.
  assert not exists (select 1 from public.film_purchase_status where purchase_id in (pid, pid2)),
         'purchase log ignores roll purchases';
  perform pg_temp.espera_error(format(
    'select public.inventory_update_purchase(gen_random_uuid(), %L, 1, 100, %L, null)', pid2, 'MXN'), 'P1109');
  perform pg_temp.espera_error(format(
    'select public.inventory_void_purchase(gen_random_uuid(), %L, 1)', pid2), 'P1109');

  -- Other account's roll, and price without currency.
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, null, 100, %L, null)', rb, 'MXN'), 'P1109');
  perform pg_temp.espera_error(format(
    'select public.film_cost_set(gen_random_uuid(), %s, null, 100, null, null)', r0), 'P1103');
  perform pg_temp.yo();
  assert not exists (select 1 from public.film_purchases where roll_id = rb), 'B roll untouched';

  -- Last: deleting the account leaves no rows and archives nothing new. The
  -- roll deleted above was archived then; account deletion does not purge
  -- earlier archives (pre-existing behavior, outside this work).
  select count(*) into archived from public.deleted_rows where dueno = a;
  perform pg_temp.como(a);
  perform public.delete_my_account();
  perform pg_temp.yo();
  assert not exists (select 1 from public.film_purchases where owner_user_id = a), 'purchases gone';
  assert (select count(*) from public.deleted_rows where dueno = a) = archived, 'no new archived copies';
  assert not exists (select 1 from public.deleted_rows where dueno = a and tabla = 'film_purchases'),
         'no archived purchases';
end $$;
