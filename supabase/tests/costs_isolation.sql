-- Costs: who may write and who may read, for every public function and every
-- table and view (ANA-184). Every account owns data here, so a zero always
-- means "not allowed to see", never "nothing there".
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migrations. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; c uuid; nn uuid; p uuid; r uuid;
  portra bigint;
  ra bigint; rb bigint; ca bigint; cb bigint;
  fr_a uuid; lab_a uuid; eq_a uuid;
  calls text[]; call text; actor uuid;
  a_before text;
  rel text; tbl text; col text;
  raw bigint; seen bigint; foreign_seen bigint;
  other uuid; other_roll bigint; other_cam bigint;
  s jsonb;
begin
  a := pg_temp.inv_user('cia');
  b := pg_temp.inv_user('cib');
  c := pg_temp.inv_user('cic');
  nn := pg_temp.inv_user('cin');
  p := pg_temp.inv_user('cip', 'pending');
  r := pg_temp.inv_user('cir', 'rejected');
  perform pg_temp.inv_member(a, 'costs');
  perform pg_temp.inv_member(b, 'costs');
  perform pg_temp.inv_member(c);
  perform pg_temp.inv_member(p, 'costs');
  perform pg_temp.inv_member(r, 'costs');
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Portra Iso', 400, 'COLOR', false) returning id into portra;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R941', gen_random_uuid(), portra, 35, 'Developed') returning id into ra;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (b, 'R942', gen_random_uuid(), portra, 35, 'Developed') returning id into rb;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Cost', 'Cam Iso A', '35mm') returning id into ca;
  insert into public.cameras (owner_user_id, maker, model, format) values (b, 'Prueba Cost', 'Cam Iso B', '35mm') returning id into cb;

  -- A and B use the functions; the others get rows directly.
  perform pg_temp.como(a);
  fr_a := (public.film_cost_set(gen_random_uuid(), ra, null, 25000, 'MXN', null) ->> 'id')::uuid;
  lab_a := (public.lab_costs_save(gen_random_uuid(), ra, '[]',
             '[{"kind":"dev_scan","amount_minor":30000,"currency":"MXN"}]') -> 'charges' -> 0 ->> 'id')::uuid;
  eq_a := (public.equipment_cost_set(gen_random_uuid(), 'camera', ca, null, 350000, 'MXN', null) ->> 'id')::uuid;
  perform pg_temp.yo();
  perform pg_temp.como(b);
  perform public.film_cost_set(gen_random_uuid(), rb, null, 1000, 'USD', null);
  perform public.lab_costs_save(gen_random_uuid(), rb, '[]', '[{"kind":"dev","amount_minor":500,"currency":"USD"}]');
  perform public.equipment_cost_set(gen_random_uuid(), 'camera', cb, null, 2000, 'USD', null);
  perform pg_temp.yo();
  foreach other in array array[c, nn, p, r] loop
    insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
    values (other, 'R950', gen_random_uuid(), portra, 35, 'Developed') returning id into other_roll;
    insert into public.cameras (owner_user_id, maker, model, format)
    values (other, 'Prueba Cost', 'Cam Otra', '35mm') returning id into other_cam;
    insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, origin, roll_id)
    values (other, portra, 35, 1, 100, 'MXN', 'roll', other_roll);
    insert into public.lab_charges (owner_user_id, roll_id, kind, amount_minor, currency)
    values (other, other_roll, 'dev_scan', 100, 'MXN');
    insert into public.equipment_purchases (owner_user_id, kind, camera_id, amount_minor, currency)
    values (other, 'camera', other_cam, 100, 'MXN');
  end loop;

  -- Writes: every public write function, as every kind of account.
  calls := array[
    format('select public.film_cost_set(gen_random_uuid(), %s, null, 100, %L, null)', ra, 'MXN'),
    format('select public.lab_costs_save(gen_random_uuid(), %s, %L, %L)', ra, '[]', '[]'),
    format('select public.equipment_cost_set(gen_random_uuid(), %L, %s, null, 1, %L, null)', 'camera', ca, 'MXN'),
    format('select public.expense_update(gen_random_uuid(), %L, %L, 1, 1, %L, null)', 'lab', lab_a, 'MXN'),
    format('select public.expense_void(gen_random_uuid(), %L, %L, 1)', 'equipment', eq_a),
    format('select public.expense_restore(gen_random_uuid(), %L, %L, 1)', 'film_roll', fr_a)
  ];
  foreach actor in array array[c, nn, p, r] loop
    perform pg_temp.como(actor);
    foreach call in array calls loop
      perform pg_temp.espera_error(call, 'P1102');
    end loop;
    perform pg_temp.yo();
  end loop;
  perform pg_temp.como(null);
  foreach call in array calls || format('select public.costs_summary(%L, null)', 'MXN') loop
    perform pg_temp.espera_error(call, '42501');
  end loop;
  perform pg_temp.yo();
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  execute 'set local role authenticated';
  foreach call in array calls loop
    perform pg_temp.espera_error(call, 'P1101');
  end loop;
  perform pg_temp.yo();

  -- B against every reference of A: not found, and A stays as it was.
  a_before := (select string_agg(id::text || version || coalesce(voided_at::text, '-'), ',' order by id)
               from (select id, version, voided_at from public.film_purchases where owner_user_id = a
                     union all select id, version, voided_at from public.lab_charges where owner_user_id = a
                     union all select id, version, voided_at from public.equipment_purchases where owner_user_id = a) t);
  perform pg_temp.como(b);
  foreach call in array calls loop
    perform pg_temp.espera_error(call, 'P1109');
  end loop;
  perform pg_temp.yo();
  assert (select string_agg(id::text || version || coalesce(voided_at::text, '-'), ',' order by id)
          from (select id, version, voided_at from public.film_purchases where owner_user_id = a
                union all select id, version, voided_at from public.lab_charges where owner_user_id = a
                union all select id, version, voided_at from public.equipment_purchases where owner_user_id = a) t)
       = a_before, 'B never touches A costs';

  -- Reads: each account sees exactly its own rows; pending and rejected none.
  -- Reads do not need the feature, so C and N still see their own rows.
  foreach rel in array array[
    'public.lab_charges', 'public.equipment_purchases', 'public.roll_costs',
    'public.expense_origins', 'public.expense_currencies'
  ] loop
    foreach actor in array array[a, b, c, nn, p, r] loop
      execute format('select count(*) from %s where owner_user_id = %L', rel, actor) into raw;
      assert raw > 0, format('%s has data for %s, so a zero below means hidden', rel, actor);
      perform pg_temp.como(actor);
      execute format('select count(*), count(*) filter (where owner_user_id <> %L) from %s', actor, rel)
        into seen, foreign_seen;
      perform pg_temp.yo();
      assert foreign_seen = 0, format('%s: %s sees rows of others', rel, actor);
      if actor in (p, r) then
        assert seen = 0, format('%s: blocked account %s sees %s rows', rel, actor, seen);
      else
        assert seen = raw, format('%s: %s sees %s of its %s rows', rel, actor, seen, raw);
      end if;
    end loop;
    perform pg_temp.como(null);
    perform pg_temp.espera_error(format('select count(*) from %s', rel), '42501');
    perform pg_temp.yo();
  end loop;

  -- The summary of a blocked account is empty although it owns expenses.
  perform pg_temp.como(p);
  s := public.costs_summary('MXN', null);
  perform pg_temp.yo();
  assert (s ->> 'total_minor')::bigint = 0, 'pending account summary is empty';

  -- The matrix notices a policy without the approved-profile condition: with
  -- it removed, the pending account would see its own charges.
  alter policy lab_charges_select_own on public.lab_charges using (owner_user_id = (select auth.uid()));
  perform pg_temp.como(p);
  select count(*) into seen from public.lab_charges;
  perform pg_temp.yo();
  assert seen > 0, 'a policy without the approved check would be caught above';
end $$;
