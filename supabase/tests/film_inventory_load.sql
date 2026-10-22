-- Film inventory: load a roll from stock, correct where it came from, and
-- delete a loaded roll with or without returning its unit.
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid;
  portra bigint; gold bigint;
  cam35 bigint; cam645 bigint; camnull bigint; cams8 bigint; lens bigint;
  camb bigint; lensb bigint; roll_b bigint;
  feb jsonb := '{"year":2027,"month":2}';
  may jsonb := '{"year":2027,"month":5}';
  l1 uuid := gen_random_uuid();
  res jsonb; res2 jsonb;
  r1 bigint; rx bigint; ry bigint; rz bigint; rw bigint; rdirect bigint;
  rolls_before bigint; units_before text;
  u_first uuid; uz uuid;
begin
  a := pg_temp.inv_user('loada');
  b := pg_temp.inv_user('loadb');
  perform pg_temp.inv_member(a);
  perform pg_temp.inv_member(b);
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Inv', 'Portra Inv', 400, 'COLOR', false) returning id into portra;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Inv', 'Gold Inv', 200, 'COLOR', false) returning id into gold;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Inv', 'Cam 35', '35mm') returning id into cam35;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Inv', 'Cam 645', '6x4.5') returning id into cam645;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Inv', 'Cam sin formato', null) returning id into camnull;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Inv', 'Cam S8', 'Super8') returning id into cams8;
  insert into public.lenses (owner_user_id, maker, model, mount) values (a, 'Prueba Inv', 'Lente A', 'M') returning id into lens;
  insert into public.cameras (owner_user_id, maker, model, format) values (b, 'Prueba Inv', 'Cam B', '35mm') returning id into camb;
  insert into public.lenses (owner_user_id, maker, model, mount) values (b, 'Prueba Inv', 'Lente B', 'M') returning id into lensb;

  perform pg_temp.como(a);
  perform public.inventory_receive(gen_random_uuid(), portra, 35, 22000, 'MXN', '2026-01-10', format('[{"quantity":2,"expiration_date":%s}]', feb)::jsonb);
  perform public.inventory_receive(gen_random_uuid(), portra, 35, 23333, 'MXN', '2026-03-05', format('[{"quantity":1,"expiration_date":%s}]', feb)::jsonb);
  perform public.inventory_receive(gen_random_uuid(), portra, 35, 21000, 'MXN', null, format('[{"quantity":1,"expiration_date":%s}]', may)::jsonb);
  perform public.inventory_receive(gen_random_uuid(), gold, 35, 18000, 'MXN', null, format('[{"quantity":1,"expiration_date":%s}]', feb)::jsonb);
  perform public.inventory_receive(gen_random_uuid(), gold, 120, 26000, 'MXN', null, '[{"quantity":2}]');
  perform public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null, '[{"quantity":1,"expiration_date":{"year":2020}}]');
  perform public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null, '[{"quantity":6,"expiration_date":{"year":2028}}]');

  -- Load: one transaction creates the roll and takes the oldest purchase.
  res := public.inventory_load(l1, portra, 35, feb, null, current_date, cam35, lens, 36, null);
  r1 := (res ->> 'roll_id')::bigint;
  u_first := (res ->> 'unit_id')::uuid;
  assert (select client_uuid from public.rolls where id = r1) = l1, 'roll keeps the command id';
  assert (select status from public.rolls where id = r1) = 'In Camera', 'roll in camera';
  assert (select started from public.rolls where id = r1) = current_date, 'started today';
  assert (select fresh from public.rolls where id = r1), 'fresh while the date is ahead';
  assert (select expiration_date from public.rolls where id = r1) = feb, 'roll inherits the expiration';
  assert (select push_pull from public.rolls where id = r1) = '0', 'push/pull defaults to 0';
  assert (select (film_stock_id, format, exp_count, camera_id, lens_id) from public.rolls where id = r1)
       = (portra, 35, 36, cam35, lens), 'roll fields';
  assert (select unit_price_minor from public.roll_film_origin where roll_id = r1) = 22000, 'cost of the oldest purchase';
  rolls_before := (select count(*) from public.rolls);
  res2 := public.inventory_load(l1, portra, 35, feb, null, current_date, cam35, lens, 36, null);
  assert res2 = res, 'load replays';
  assert (select count(*) from public.rolls) = rolls_before, 'replay creates no roll';
  assert (select available from public.film_inventory_lines where film_stock_id = portra and expiration_date = feb) = 2, 'replay takes no unit';

  res := public.inventory_load(gen_random_uuid(), portra, 35, feb, null, current_date, cam35, null, 36, null);
  assert (select unit_price_minor from public.roll_film_origin where roll_id = (res ->> 'roll_id')::bigint) = 22000, 'second from the first purchase';
  res := public.inventory_load(gen_random_uuid(), portra, 35, feb, null, current_date, cam35, null, 36, null);
  assert (select unit_price_minor from public.roll_film_origin where roll_id = (res ->> 'roll_id')::bigint) = 23333, 'then the next purchase';
  rolls_before := (select count(*) from public.rolls);
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 36, null)',
    gen_random_uuid(), portra, feb, cam35), 'P1104');
  assert (select count(*) from public.rolls) = rolls_before, 'no stock, no roll';

  -- An expired printed date makes an expired roll.
  res := public.inventory_load(gen_random_uuid(), portra, 35, '{"year":2020}', null, current_date, cam35, null, 36, null);
  assert (select fresh from public.rolls where id = (res ->> 'roll_id')::bigint) = false, 'expired roll';
  assert (select expiration_year from public.rolls where id = (res ->> 'roll_id')::bigint) = 2020, 'legacy year kept in sync';

  -- 120 from a 6x4.5 camera.
  res := public.inventory_load(gen_random_uuid(), gold, 120, null, null, current_date, cam645, null, 15, '+1');
  assert (select (format, push_pull) from public.rolls where id = (res ->> 'roll_id')::bigint) = (120, '+1'::text), '120 roll';

  -- Rejected loads change nothing.
  rolls_before := (select count(*) from public.rolls);
  units_before := (select string_agg(status, ',' order by id) from public.film_units);
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 36, null)',
    gen_random_uuid(), portra, '{"year":2028}', cam645), 'P1107');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 36, null)',
    gen_random_uuid(), portra, '{"year":2028}', camnull), 'P1107');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 36, null)',
    gen_random_uuid(), portra, '{"year":2028}', cams8), 'P1107');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, %s, 36, null)',
    gen_random_uuid(), portra, '{"year":2028}', cam35, lensb), 'P1109');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 36, null)',
    gen_random_uuid(), portra, '{"year":2028}', camb), 'P1109');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date + 3, %s, null, 36, null)',
    gen_random_uuid(), portra, '{"year":2028}', cam35), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 0, null)',
    gen_random_uuid(), portra, '{"year":2028}', cam35), 'P1103');
  assert (select count(*) from public.rolls) = rolls_before, 'rejected loads create no roll';
  assert (select string_agg(status, ',' order by id) from public.film_units) = units_before, 'rejected loads move no unit';

  -- Offline: a load queued days ago keeps its day and its moment, like the
  -- direct roll insert does.
  res := public.inventory_load(gen_random_uuid(), portra, 35, '{"year":2028}', null, current_date - 10,
                               cam35, null, 36, null, (current_date - 10) + time '15:00');
  assert (select started from public.rolls where id = (res ->> 'roll_id')::bigint) = current_date - 10, 'offline load keeps its day';
  assert (select created_at from public.rolls where id = (res ->> 'roll_id')::bigint)
       = ((current_date - 10) + time '15:00')::timestamptz, 'offline load keeps its moment';
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date - 400, %s, null, 36, null, null)',
    gen_random_uuid(), portra, '{"year":2028}', cam35), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 36, null, now() - interval %L)',
    gen_random_uuid(), portra, '{"year":2028}', cam35, '5 days'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_load(%L, %s, 35, %L, null, current_date, %s, null, 36, null, now() + interval %L)',
    gen_random_uuid(), portra, '{"year":2028}', cam35, '3 days'), 'P1103');
  perform pg_temp.yo();

  -- Codes follow the app rule and never truncate.
  insert into public.rolls (owner_user_id, code, client_uuid) values
    (a, 'R-012', gen_random_uuid()), (a, 'r7', gen_random_uuid()), (a, 'X1', gen_random_uuid()), (a, 'R999', gen_random_uuid());
  perform pg_temp.como(a);
  res := public.inventory_load(gen_random_uuid(), portra, 35, '{"year":2028}', null, current_date, cam35, null, 36, null);
  rz := (res ->> 'roll_id')::bigint;
  uz := (res ->> 'unit_id')::uuid;
  assert res ->> 'code' = 'R1000', 'next code after R999 is R1000';
  perform pg_temp.yo();
  perform pg_temp.como(b);
  perform public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null, '[{"quantity":1}]');
  res := public.inventory_load(gen_random_uuid(), portra, 35, null, null, current_date, camb, null, 36, null);
  roll_b := (res ->> 'roll_id')::bigint;
  assert res ->> 'code' = 'R001', 'first code of an account';
  perform pg_temp.yo();

  -- The usual way of creating, editing and deleting rolls is untouched.
  perform pg_temp.como(a);
  units_before := (select string_agg(status || coalesce(roll_id::text, '-'), ',' order by id) from public.film_units);
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R2000', gen_random_uuid(), portra, 35, 'In Camera') returning id into rdirect;
  update public.rolls set notes = 'x' where id = rdirect;
  delete from public.rolls where id = rdirect;
  assert (select string_agg(status || coalesce(roll_id::text, '-'), ',' order by id) from public.film_units) = units_before,
         'plain rolls do not touch the inventory';

  -- Correct where the roll came from.
  res := public.inventory_swap(gen_random_uuid(), r1, portra, 35, may, null);
  assert (select status from public.film_units where id = u_first) = 'available', 'original unit returned';
  assert (select expiration_date from public.rolls where id = r1) = may, 'roll takes the new expiration';
  assert (select available from public.film_inventory_lines where film_stock_id = portra and expiration_date = feb) = 1, 'unit back in its line';
  res2 := public.inventory_swap(gen_random_uuid(), r1, portra, 35, may, null);
  assert res2 ->> 'unit_id' = res ->> 'unit_id', 'same line keeps the same unit';
  res := public.inventory_swap(gen_random_uuid(), r1, gold, 35, feb, null);
  assert (select film_stock_id from public.rolls where id = r1) = gold, 'another film of the same format';
  assert (select unit_price_minor from public.roll_film_origin where roll_id = r1) = 18000, 'cost follows the new unit';
  perform pg_temp.espera_error(format('select public.inventory_swap(%L, %s, %s, 120, null, null)',
    gen_random_uuid(), r1, gold), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_swap(%L, %s, %s, 35, %L, null)',
    gen_random_uuid(), r1, gold, may), 'P1104');
  perform pg_temp.espera_error(format('select public.inventory_swap(%L, %s, %s, 35, %L, null)',
    gen_random_uuid(), roll_b, portra, feb), 'P1109');
  -- Edited the usual way after loading, then corrected to its own line: the
  -- unit stays and the roll goes back to matching it.
  update public.rolls set film_stock_id = portra, expiration_date = '{"year":2030}' where id = r1;
  res := public.inventory_swap(gen_random_uuid(), r1, gold, 35, feb, null);
  assert (select (film_stock_id, expiration_date::jsonb, fresh) from public.rolls where id = r1)
       = (gold, feb, true), 'same-line correction reconciles the roll';
  assert (select unit_price_minor from public.roll_film_origin where roll_id = r1) = 18000, 'same unit, same cost';
  -- rolls.expiration_date is the film_expiration_date domain: only the date
  -- changed here, so the comparison reaches that column.
  update public.rolls set expiration_date = '{"year":2031}' where id = r1;
  res := public.inventory_swap(gen_random_uuid(), r1, gold, 35, feb, null);
  assert (select expiration_date::jsonb from public.rolls where id = r1) = feb, 'date-only edit reconciled';

  -- Delete a loaded roll with eight frames and return its unit.
  res := public.inventory_load(gen_random_uuid(), portra, 35, '{"year":2028}', null, current_date, cam35, null, 36, null);
  rx := (res ->> 'roll_id')::bigint;
  perform pg_temp.yo();
  insert into public.roll_exposures (roll_id, frame_number) select rx, n from generate_series(1, 8) n;
  perform pg_temp.como(a);
  res2 := public.inventory_delete_roll(gen_random_uuid(), rx, true);
  assert (res2 ->> 'returned')::boolean, 'reported as returned';
  assert not exists (select 1 from public.rolls where id = rx), 'roll deleted';
  assert (select status from public.film_units where id = (res ->> 'unit_id')::uuid) = 'available', 'unit back in stock';
  res := public.inventory_load(gen_random_uuid(), portra, 35, '{"year":2028}', null, current_date, cam35, null, 36, null);
  ry := (res ->> 'roll_id')::bigint;
  perform public.inventory_delete_roll(gen_random_uuid(), ry, false);
  assert (select (status, roll_id) from public.film_units where id = (res ->> 'unit_id')::uuid)
       is not distinct from ('loaded'::text, null::bigint), 'unit stays used';
  insert into public.rolls (owner_user_id, code, client_uuid) values (a, 'R3000', gen_random_uuid()) returning id into rdirect;
  perform pg_temp.espera_error(format('select public.inventory_delete_roll(%L, %s, true)', gen_random_uuid(), rdirect), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_delete_roll(%L, %s, true)', gen_random_uuid(), roll_b), 'P1109');

  -- Deleting or editing a loaded roll the usual way.
  delete from public.rolls where id = rz;
  assert (select (status, roll_id) from public.film_units where id = uz)
       is not distinct from ('loaded'::text, null::bigint), 'directly deleted roll leaves the unit used';
  res := public.inventory_load(gen_random_uuid(), portra, 35, '{"year":2028}', null, current_date, cam35, null, 36, null);
  rw := (res ->> 'roll_id')::bigint;
  update public.rolls set film_stock_id = gold where id = rw;
  assert (select roll_id from public.film_units where id = (res ->> 'unit_id')::uuid) = rw, 'edited roll keeps its unit';
  perform pg_temp.yo();

  -- Balance: every purchase keeps exactly the units it bought.
  assert not exists (
    select 1 from public.film_purchases p
    where p.owner_user_id = a
      and (select count(*) from public.film_units u where u.purchase_id = p.id) <> p.quantity
  ), 'each purchase has its units';
end $$;
