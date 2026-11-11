-- Film inventory tables, rules and read views (ANA-173).
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; p uuid; r uuid;
  portra bigint; gold bigint;
  pa1 uuid; pa2 uuid; pa3 uuid; pa4 uuid; pb uuid; pp uuid; pr uuid;
  u public.film_units;
  roll_a bigint;
begin
  -- Printed expiration: year, or month and year, nothing else.
  assert app_private.normalize_expiration('{"year":2027}') = '{"year":2027}', 'year only';
  assert app_private.normalize_expiration('{"year":2027,"month":2}') = '{"year":2027,"month":2}', 'month kept';
  assert app_private.normalize_expiration('{"month":2,"year":2027.0}') = '{"year":2027,"month":2}', 'whole numbers normalized';
  assert app_private.normalize_expiration(null) is null, 'no date';
  perform pg_temp.espera_error($q$select app_private.normalize_expiration('{"year":999}')$q$, 'P1103');
  perform pg_temp.espera_error($q$select app_private.normalize_expiration('{"year":2027,"month":13}')$q$, 'P1103');
  perform pg_temp.espera_error($q$select app_private.normalize_expiration('{"year":2027,"day":1}')$q$, 'P1103');
  perform pg_temp.espera_error($q$select app_private.normalize_expiration('{"year":2027.5}')$q$, 'P1103');
  perform pg_temp.espera_error($q$select app_private.normalize_expiration('"2027"')$q$, 'P1103');

  -- Expired is computed from the printed date; without a date, as declared.
  assert not app_private.film_unit_expired('{"year":2026,"month":9}', true, '2026-09-30'), 'last day of month still fresh';
  assert app_private.film_unit_expired('{"year":2026,"month":9}', true, '2026-10-01'), 'next day expired';
  assert not app_private.film_unit_expired('{"year":2026}', true, '2026-12-31'), 'year lasts to Dec 31';
  assert app_private.film_unit_expired('{"year":2026}', true, '2027-01-01'), 'expired after the year';
  assert not app_private.film_unit_expired(null, true, '2026-10-21'), 'undated fresh';
  assert app_private.film_unit_expired(null, false, '2026-10-21'), 'undated declared expired';
  assert not app_private.film_unit_expired('{"year":2030}', false, '2026-10-21'), 'date wins over declaration';

  -- The device date may be up to a day ahead (time zones) and up to a year
  -- behind (a load queued offline syncs later), never further.
  perform app_private.check_local_date(current_date - 1);
  perform app_private.check_local_date(current_date + 1);
  perform app_private.check_local_date(current_date - 10);
  perform pg_temp.espera_error('select app_private.check_local_date(current_date + 2)', 'P1103');
  perform pg_temp.espera_error('select app_private.check_local_date(current_date - 400)', 'P1103');
  perform pg_temp.espera_error('select app_private.check_local_date(null)', 'P1103');

  a := pg_temp.inv_user('taba');
  b := pg_temp.inv_user('tabb');
  p := pg_temp.inv_user('tabp', 'pending');
  r := pg_temp.inv_user('tabr', 'rejected');
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Inv', 'Portra Inv', 400, 'COLOR', false) returning id into portra;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Inv', 'Gold Inv', 200, 'COLOR', false) returning id into gold;

  -- A: two priced purchases and one without price, same Portra line.
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on)
  values (a, portra, 35, 2, 22000, 'MXN', '2026-01-10') returning id into pa1;
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on)
  values (a, portra, 35, 1, 23333, 'MXN', '2026-03-05') returning id into pa2;
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity)
  values (a, portra, 35, 1) returning id into pa3;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, expiration_date)
  select a, pa1, portra, 35, '{"year":2027,"month":2}'::jsonb from generate_series(1, 2)
  union all select a, pa2, portra, 35, '{"year":2027,"month":2}'::jsonb
  union all select a, pa3, portra, 35, '{"year":2027,"month":2}'::jsonb;
  -- A: one Gold unit already loaded into a roll.
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency)
  values (a, gold, 35, 1, 18000, 'MXN') returning id into pa4;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R901', gen_random_uuid(), gold, 35, 'In Camera') returning id into roll_a;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, status, roll_id, loaded_on)
  values (a, pa4, gold, 35, 'loaded', roll_a, current_date);
  -- B, pending and rejected each have their own stock.
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity) values (b, portra, 35, 1) returning id into pb;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format) values (b, pb, portra, 35);
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity) values (p, portra, 35, 1) returning id into pp;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format) values (p, pp, portra, 35);
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity) values (r, portra, 35, 1) returning id into pr;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format) values (r, pr, portra, 35);

  -- Price and currency go together; the format is a physical roll.
  perform pg_temp.espera_error(format('insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor) values (%L, %s, 35, 1, 100)', a, portra), '23514');
  perform pg_temp.espera_error(format('insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity) values (%L, %s, 8, 1)', a, portra), '23514');
  perform pg_temp.espera_error(format('insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, status) values (%L, %L, %s, 35, %L)', a, pa1, portra, 'loaded'), '23514');

  -- A line is film + format + date, and without a date, the declaration.
  select * into u from public.film_units where purchase_id = pa1 limit 1;
  assert app_private.unit_in_line(u, portra, 35, '{"year":2027,"month":2}', false), 'dated unit ignores declaration';
  assert not app_private.unit_in_line(u, portra, 35, '{"year":2027}', null), 'different precision is another line';
  assert not app_private.unit_in_line(u, gold, 35, '{"year":2027,"month":2}', null), 'other film is another line';
  assert not app_private.unit_in_line(u, portra, 120, '{"year":2027,"month":2}', null), 'other format is another line';
  u.expiration_date := null;
  u.declared_fresh := false;
  assert app_private.unit_in_line(u, portra, 35, null, false), 'undated expired line';
  assert not app_private.unit_in_line(u, portra, 35, null, null), 'undated defaults to fresh';

  -- Read views for A.
  perform pg_temp.como(a);
  assert (select count(*) from public.film_purchases) = 4, 'A reads its purchases only';
  assert (select count(*) from public.film_units) = 5, 'A reads its units only';
  assert (select count(*) from public.film_inventory_lines) = 1, 'one available line';
  assert (select available from public.film_inventory_lines) = 4, 'four available';
  assert (select unpriced from public.film_inventory_lines) = 1, 'one without price';
  assert (select prices from public.film_inventory_lines)
       = '[{"currency":"MXN","units":3,"min_minor":22000,"max_minor":23333,"avg_minor":22444}]'::jsonb,
         'price summary per currency';
  assert (select line_declared_fresh from public.film_inventory_lines) is null, 'dated line has no declaration';
  assert (select loaded from public.film_purchase_status where purchase_id = pa4) = 1, 'loaded unit counted';
  assert (select available from public.film_purchase_status where purchase_id = pa1) = 2, 'available per purchase';
  assert (select unit_price_minor from public.roll_film_origin where roll_id = roll_a) = 18000, 'roll cost from its purchase';
  perform pg_temp.espera_error(format('insert into public.film_units (owner_user_id, film_stock_id, format) values (%L, %s, 35)', a, portra), '42501');
  perform pg_temp.espera_error('update public.film_units set status = ''removed''', '42501');
  perform pg_temp.espera_error('delete from public.film_purchases', '42501');
  perform pg_temp.yo();

  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency)
  values (a, portra, 35, 1, 1500, 'USD') returning id into pa1;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, expiration_date)
  values (a, pa1, portra, 35, '{"year":2027,"month":2}');
  perform pg_temp.como(a);
  assert (select prices from public.film_inventory_lines)
       = '[{"currency":"MXN","units":3,"min_minor":22000,"max_minor":23333,"avg_minor":22444},
           {"currency":"USD","units":1,"min_minor":1500,"max_minor":1500,"avg_minor":1500}]'::jsonb,
         'currencies never mix';
  perform pg_temp.yo();

  perform pg_temp.como(b);
  assert (select count(*) from public.film_units) = 1, 'B reads only its unit';
  assert (select count(*) from public.roll_film_origin) = 0, 'B cannot see A roll cost';
  perform pg_temp.yo();
  perform pg_temp.como(p);
  assert (select count(*) from public.film_units) = 0, 'pending reads nothing';
  assert (select count(*) from public.film_purchases) = 0, 'pending reads no purchases';
  perform pg_temp.yo();
  perform pg_temp.como(r);
  assert (select count(*) from public.film_inventory_lines) = 0, 'rejected reads nothing';
  perform pg_temp.yo();
  perform pg_temp.como(null);
  perform pg_temp.espera_error('select count(*) from public.film_units', '42501');
  perform pg_temp.espera_error('select count(*) from public.film_inventory_lines', '42501');
  perform pg_temp.yo();

  -- Last: deleting the account leaves nothing, not even an archived copy.
  -- delete_my_account keeps app.borrando_cuenta on for the rest of the
  -- transaction, so nothing may follow it.
  perform pg_temp.como(a);
  perform public.delete_my_account();
  perform pg_temp.yo();
  assert not exists (select 1 from public.film_purchases where owner_user_id = a), 'purchases gone';
  assert not exists (select 1 from public.film_units where owner_user_id = a), 'units gone';
  assert not exists (select 1 from public.deleted_rows where dueno = a), 'no archived copies';
  assert exists (select 1 from public.film_units where owner_user_id = b), 'other accounts untouched';
end $$;
