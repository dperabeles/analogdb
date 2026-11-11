-- Cifras: every number of costs_summary against a case built by hand, with
-- known values (ANA-184). Run inside BEGIN / ROLLBACK after
-- film_inventory_helpers.sql, also immediately after applying the migration.
-- Synthetic accounts only.
do $$
declare
  a uuid; b uuid;
  p bigint; g bigint; l1 bigint; l2 bigint; c1 bigint; c2 bigint; z1 bigint; z2 bigint; cb bigint;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid;
  r1 bigint; r2 bigint; r3 bigint; r4 bigint; r5 bigint; r6 bigint;
  s jsonb;
begin
  a := pg_temp.inv_user('csa');
  b := pg_temp.inv_user('csb');
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Portra Sum', 400, 'COLOR', false) returning id into p;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Gold Sum', 200, 'COLOR', false) returning id into g;
  insert into public.labs (name, status) values ('Lab Costos Sum Uno', 'approved') returning id into l1;
  insert into public.labs (name, status) values ('Lab Costos Sum Dos', 'approved') returning id into l2;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Sum', '35mm') returning id into c1;
  -- A camera nobody priced: it only counts as missing in all time.
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Sum Dos', '35mm') returning id into c2;
  insert into public.lenses (owner_user_id, maker, model, mount) values (a, 'Prueba Cost', 'Lente Sum Uno', 'M') returning id into z1;
  insert into public.lenses (owner_user_id, maker, model, mount) values (a, 'Prueba Cost', 'Lente Sum Dos', 'M') returning id into z2;
  insert into public.cameras (owner_user_id, maker, model, format) values (b, 'Prueba Cost', 'Cam Sum B', '35mm') returning id into cb;

  -- Inventory purchases.
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on)
  values (a, p, 35, 2, 20000, 'MXN', '2026-01-10') returning id into p1;
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on)
  values (a, g, 35, 1, 0, 'MXN', '2026-02-01') returning id into p2;
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, purchased_on)
  values (a, p, 35, 1, '2026-03-01') returning id into p3;
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on)
  values (a, p, 35, 1, 1500, 'USD', '2026-02-15') returning id into p4;
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on)
  values (a, g, 35, 1, 1200, 'JPY', '2026-09-09') returning id into p5;

  -- Rolls.
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, finished, dev_lab_id)
  values (a, 'R931', gen_random_uuid(), p, 35, 'Developed', '2026-05-20', l1) returning id into r1;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, finished, dev_lab_id, scan_lab_id)
  values (a, 'R932', gen_random_uuid(), g, 35, 'Developed', '2026-06-01', l1, l2) returning id into r2;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, finished, dev_lab_id)
  values (a, 'R933', gen_random_uuid(), p, 35, 'Archived', '2025-11-30', l2) returning id into r3;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, finished)
  values (a, 'R934', gen_random_uuid(), p, 35, 'Developed', '2026-07-01') returning id into r4;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, finished, dev_lab_id)
  values (a, 'R935', gen_random_uuid(), p, 35, 'Developed', '2026-08-01', l1) returning id into r5;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R936', gen_random_uuid(), p, 35, 'Developed') returning id into r6;

  -- Units: one of p1 loaded in R1, p2 loaded in R2; the rest available.
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, status, roll_id, loaded_on) values
    (a, p1, p, 35, 'loaded', r1, '2026-05-01'),
    (a, p2, g, 35, 'loaded', r2, '2026-05-15');
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format) values
    (a, p1, p, 35), (a, p3, p, 35), (a, p4, p, 35), (a, p5, g, 35);

  -- Film price of rolls outside the inventory.
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on, origin, roll_id) values
    (a, p, 35, 1, 25000, 'MXN', null, 'roll', r3),
    (a, p, 35, 1, 21000, 'MXN', '2026-06-20', 'roll', r4),
    (a, p, 35, 1, 2000, 'USD', '2026-07-05', 'roll', r5);

  -- Lab charges.
  insert into public.lab_charges (owner_user_id, roll_id, kind, amount_minor, currency, charged_on) values
    (a, r1, 'dev_scan', 18000, 'MXN', '2026-05-02'),
    (a, r2, 'dev', 9000, 'MXN', '2026-06-03'),
    (a, r2, 'scan', 0, 'MXN', '2026-06-03'),
    (a, r3, 'dev_scan', 20000, 'MXN', null),
    (a, r5, 'dev_scan', 15000, 'MXN', '2026-08-02');

  -- Gear: one priced, one known by date only, one voided; B's own camera.
  insert into public.equipment_purchases (owner_user_id, kind, camera_id, amount_minor, currency, purchased_on)
  values (a, 'camera', c1, 350000, 'MXN', '2026-04-04');
  insert into public.equipment_purchases (owner_user_id, kind, lens_id, purchased_on)
  values (a, 'lens', z1, '2026-04-04');
  insert into public.equipment_purchases (owner_user_id, kind, lens_id, amount_minor, currency, purchased_on, voided_at)
  values (a, 'lens', z2, 50000, 'MXN', '2026-04-10', now());
  insert into public.equipment_purchases (owner_user_id, kind, camera_id, amount_minor, currency, purchased_on)
  values (b, 'camera', cb, 99999, 'MXN', '2026-01-01');

  perform pg_temp.como(a);

  -- MXN, 2026.
  s := public.costs_summary('MXN', 2026);
  assert s ->> 'currency' = 'MXN' and (s ->> 'year')::int = 2026, 'echoes the filter';
  assert (s ->> 'total_minor')::bigint = 453000, format('total 2026: %s', s ->> 'total_minor');
  assert (s ->> 'undated_minor')::bigint = 0, 'a year has no undated';
  assert s -> 'evolution' = '[{"period":1,"amount_minor":40000},{"period":2,"amount_minor":0},
    {"period":3,"amount_minor":0},{"period":4,"amount_minor":350000},{"period":5,"amount_minor":18000},
    {"period":6,"amount_minor":30000},{"period":7,"amount_minor":0},{"period":8,"amount_minor":15000},
    {"period":9,"amount_minor":0},{"period":10,"amount_minor":0},{"period":11,"amount_minor":0},
    {"period":12,"amount_minor":0}]'::jsonb, format('evolution 2026: %s', s -> 'evolution');
  assert s -> 'breakdown' = '[{"category":"film","amount_minor":61000},{"category":"dev_scan","amount_minor":33000},
    {"category":"dev","amount_minor":9000},{"category":"scan","amount_minor":0},
    {"category":"camera","amount_minor":350000},{"category":"lens","amount_minor":0}]'::jsonb,
    format('breakdown 2026: %s', s -> 'breakdown');
  assert s -> 'film_avg' = '{"avg_minor":20333,"units":3}'::jsonb, format('film avg 2026: %s', s -> 'film_avg');
  assert s -> 'roll_avg' = '{"avg_minor":23500,"rolls_counted":2,"rolls_finished":4,"rolls_without_finish":1}'::jsonb,
    format('roll avg 2026: %s', s -> 'roll_avg');
  assert s -> 'inventory' = '{"value_minor":20000,"units_priced":1,"units_unpriced":1}'::jsonb,
    format('inventory: %s', s -> 'inventory');
  assert s -> 'film_details' = jsonb_build_array(
    jsonb_build_object('film_stock_id', p, 'format', 35, 'amount_minor', 61000, 'units', 3),
    jsonb_build_object('film_stock_id', g, 'format', 35, 'amount_minor', 0, 'units', 1)),
    format('film details 2026: %s', s -> 'film_details');
  assert s -> 'lab_details' = jsonb_build_array(
    jsonb_build_object('lab_id', l1, 'dev_scan_minor', 33000, 'dev_minor', 9000, 'scan_minor', 0, 'amount_minor', 42000),
    jsonb_build_object('lab_id', l2, 'dev_scan_minor', 0, 'dev_minor', 0, 'scan_minor', 0, 'amount_minor', 0)),
    format('lab details 2026: %s', s -> 'lab_details');
  assert s -> 'coverage' = '{"film_units_unpriced":1,"equipment_unpriced":1}'::jsonb, format('coverage: %s', s -> 'coverage');

  -- MXN, all time: undated expenses count here and only here.
  s := public.costs_summary('MXN', null);
  assert s -> 'year' = 'null'::jsonb, 'all time has no year';
  assert (s ->> 'total_minor')::bigint = 498000, format('total all: %s', s ->> 'total_minor');
  assert (s ->> 'undated_minor')::bigint = 45000, 'undated all';
  assert s -> 'evolution' = '[{"period":2026,"amount_minor":453000}]'::jsonb, format('evolution all: %s', s -> 'evolution');
  assert (select (e ->> 'amount_minor')::bigint from jsonb_array_elements(s -> 'breakdown') e where e ->> 'category' = 'film') = 86000, 'film all';
  assert (select (e ->> 'amount_minor')::bigint from jsonb_array_elements(s -> 'breakdown') e where e ->> 'category' = 'dev_scan') = 53000, 'dev_scan all';
  assert s -> 'film_avg' = '{"avg_minor":21500,"units":4}'::jsonb, format('film avg all: %s', s -> 'film_avg');
  assert s -> 'roll_avg' = '{"avg_minor":30667,"rolls_counted":3,"rolls_finished":6,"rolls_without_finish":1}'::jsonb,
    format('roll avg all: %s', s -> 'roll_avg');
  assert (select e from jsonb_array_elements(s -> 'lab_details') e where (e ->> 'lab_id')::bigint = l2)
       = jsonb_build_object('lab_id', l2, 'dev_scan_minor', 20000, 'dev_minor', 0, 'scan_minor', 0, 'amount_minor', 20000),
       'L2 all time';
  -- Gear without price in all time: Z1 (date only), Z2 (its only purchase was
  -- voided) and C2 (never priced). A year only counts dated purchases.
  assert s -> 'coverage' = '{"film_units_unpriced":1,"equipment_unpriced":3}'::jsonb, format('coverage all: %s', s -> 'coverage');

  -- 2025: no payments, but R3 was finished then.
  s := public.costs_summary('MXN', 2025);
  assert (s ->> 'total_minor')::bigint = 0, 'nothing paid in 2025';
  assert s -> 'roll_avg' = '{"avg_minor":45000,"rolls_counted":1,"rolls_finished":1,"rolls_without_finish":1}'::jsonb,
    format('roll avg 2025: %s', s -> 'roll_avg');

  -- USD and JPY never mix with MXN.
  s := public.costs_summary('USD', 2026);
  assert (s ->> 'total_minor')::bigint = 3500, 'USD total';
  assert s -> 'film_avg' = '{"avg_minor":1750,"units":2}'::jsonb, 'USD film avg';
  assert (s -> 'roll_avg' ->> 'rolls_counted')::int = 0 and s -> 'roll_avg' -> 'avg_minor' = 'null'::jsonb,
         'mixed currency roll counts nowhere';
  assert s -> 'inventory' = '{"value_minor":1500,"units_priced":1,"units_unpriced":1}'::jsonb, 'USD inventory';
  s := public.costs_summary('JPY', null);
  assert (s ->> 'total_minor')::bigint = 1200, 'JPY total, no decimals';
  assert (select array_agg(currency::text order by currency) from public.expense_currencies) = array['JPY', 'MXN', 'USD'],
         'currencies with expenses';

  -- A year without expenses: zeros, twelve months, no averages.
  s := public.costs_summary('MXN', 2030);
  assert (s ->> 'total_minor')::bigint = 0 and (s ->> 'undated_minor')::bigint = 0, 'empty year totals';
  assert jsonb_array_length(s -> 'evolution') = 12
     and (select sum((e ->> 'amount_minor')::bigint) from jsonb_array_elements(s -> 'evolution') e) = 0, 'twelve empty months';
  assert s -> 'film_avg' = '{"avg_minor":null,"units":0}'::jsonb, 'no film average';
  assert s -> 'roll_avg' = '{"avg_minor":null,"rolls_counted":0,"rolls_finished":0,"rolls_without_finish":1}'::jsonb, 'no roll average';
  assert s -> 'film_details' = '[]'::jsonb and s -> 'lab_details' = '[]'::jsonb, 'no details';
  assert s -> 'coverage' = '{"film_units_unpriced":0,"equipment_unpriced":0}'::jsonb, 'nothing missing';

  perform pg_temp.espera_error($q$select public.costs_summary('ZZZ', null)$q$, 'P1103');
  perform pg_temp.espera_error($q$select public.costs_summary('MXN', 99999)$q$, 'P1103');
  perform pg_temp.yo();

  -- The film expense follows its roll: clearing the roll's film groups it as
  -- "no film" instead of the film it was priced with.
  update public.rolls set film_stock_id = null where id = r4;
  perform pg_temp.como(a);
  s := public.costs_summary('MXN', 2026);
  assert s -> 'film_details' = jsonb_build_array(
    jsonb_build_object('film_stock_id', p, 'format', 35, 'amount_minor', 40000, 'units', 2),
    jsonb_build_object('film_stock_id', null, 'format', 35, 'amount_minor', 21000, 'units', 1),
    jsonb_build_object('film_stock_id', g, 'format', 35, 'amount_minor', 0, 'units', 1)),
    format('film details without film: %s', s -> 'film_details');
  perform pg_temp.yo();

  -- B sees only its own camera.
  perform pg_temp.como(b);
  s := public.costs_summary('MXN', null);
  assert (s ->> 'total_minor')::bigint = 99999, 'B total is its own';
  assert (s -> 'roll_avg' ->> 'rolls_finished')::int = 0 and (s -> 'inventory' ->> 'units_unpriced')::int = 0, 'B sees no rolls or stock of A';
  perform pg_temp.yo();
end $$;
