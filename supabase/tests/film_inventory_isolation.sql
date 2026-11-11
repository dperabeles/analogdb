-- Film inventory: who may write and who may read, for every public function
-- and every table and view. Every account owns data here, so a zero always
-- means "not allowed to see", never "nothing there".
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migrations. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; c uuid; p uuid; r uuid;
  portra bigint; cam_a bigint; cam_b bigint;
  pur_a uuid; roll_a bigint; res jsonb;
  y2027 jsonb := '{"year":2027}';
  calls text[]; call text; actor uuid;
  a_before text;
  rel text; tbl text; col text;
  raw bigint; seen bigint; foreign_seen bigint;
  other uuid; other_purchase uuid; other_roll bigint;
begin
  a := pg_temp.inv_user('isoa');
  b := pg_temp.inv_user('isob');
  c := pg_temp.inv_user('isoc');
  p := pg_temp.inv_user('isop', 'pending');
  r := pg_temp.inv_user('isor', 'rejected');
  perform pg_temp.inv_member(a);
  perform pg_temp.inv_member(b);
  perform pg_temp.inv_member(p);
  perform pg_temp.inv_member(r);
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Inv', 'Portra Inv', 400, 'COLOR', false) returning id into portra;
  insert into public.cameras (owner_user_id, maker, model, format) values (a, 'Prueba Inv', 'Cam A', '35mm') returning id into cam_a;
  insert into public.cameras (owner_user_id, maker, model, format) values (b, 'Prueba Inv', 'Cam B', '35mm') returning id into cam_b;

  -- A and B use the functions; C, pending and rejected get rows directly.
  perform pg_temp.como(a);
  perform public.set_default_currency('MXN');
  res := public.inventory_receive(gen_random_uuid(), portra, 35, 20000, 'MXN', null,
                                  format('[{"quantity":3,"expiration_date":%s}]', y2027)::jsonb);
  pur_a := (res ->> 'purchase_id')::uuid;
  res := public.inventory_load(gen_random_uuid(), portra, 35, y2027, null, current_date, cam_a, null, 36, null);
  roll_a := (res ->> 'roll_id')::bigint;
  perform pg_temp.yo();
  perform pg_temp.como(b);
  perform public.set_default_currency('USD');
  perform public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null,
                                   format('[{"quantity":2,"expiration_date":%s}]', y2027)::jsonb);
  perform pg_temp.yo();
  foreach other in array array[c, p, r] loop
    insert into public.finance_preferences (user_id, default_currency) values (other, 'MXN');
    insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency)
    values (other, portra, 35, 2, 100, 'MXN') returning id into other_purchase;
    insert into public.rolls (owner_user_id, code, client_uuid) values (other, 'R950', gen_random_uuid())
    returning id into other_roll;
    insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format) values (other, other_purchase, portra, 35);
    insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format, status, roll_id, loaded_on)
    values (other, other_purchase, portra, 35, 'loaded', other_roll, current_date);
    insert into public.inventory_commands (command_id, owner_user_id, kind, request_hash, result)
    values (gen_random_uuid(), other, 'receive', 'x', '{}');
  end loop;

  -- Writes: every public function, as every kind of account.
  calls := array[
    format('select public.set_default_currency(%L)', 'MXN'),
    format('select public.inventory_receive(gen_random_uuid(), %s, 35, null, null, null, %L)', portra, '[{"quantity":1}]'),
    format('select public.inventory_adjust(gen_random_uuid(), %s, 35, %L, null, 0, 1)', portra, y2027),
    format('select public.inventory_update_purchase(gen_random_uuid(), %L, 1, 1, %L, null)', pur_a, 'MXN'),
    format('select public.inventory_void_purchase(gen_random_uuid(), %L, 1)', pur_a),
    format('select public.inventory_load(gen_random_uuid(), %s, 35, %L, null, current_date, %s, null, 36, null)', portra, y2027, cam_a),
    format('select public.inventory_swap(gen_random_uuid(), %s, %s, 35, null, null)', roll_a, portra),
    format('select public.inventory_delete_roll(gen_random_uuid(), %s, true)', roll_a)
  ];
  foreach actor in array array[c, p, r] loop
    perform pg_temp.como(actor);
    foreach call in array calls loop
      perform pg_temp.espera_error(call, 'P1102');
    end loop;
    perform pg_temp.yo();
  end loop;
  perform pg_temp.como(null);
  foreach call in array calls loop
    perform pg_temp.espera_error(call, '42501');
  end loop;
  perform pg_temp.yo();
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  execute 'set local role authenticated';
  foreach call in array calls loop
    perform pg_temp.espera_error(call, 'P1101');
  end loop;
  perform pg_temp.yo();

  -- B against A's purchase, roll and camera; B's own line calls only touch B.
  a_before := (select string_agg(id::text || status || coalesce(roll_id::text, '-'), ',' order by id)
               from public.film_units where owner_user_id = a);
  perform pg_temp.como(b);
  foreach call in array calls[4:8] loop
    perform pg_temp.espera_error(call, 'P1109');
  end loop;
  perform public.inventory_load(gen_random_uuid(), portra, 35, y2027, null, current_date, cam_b, null, 36, null);
  perform public.inventory_adjust(gen_random_uuid(), portra, 35, y2027, null, 1, 0);
  perform pg_temp.espera_error(format('select public.inventory_load(gen_random_uuid(), %s, 35, %L, null, current_date, %s, null, 36, null)',
    portra, y2027, cam_b), 'P1104');
  -- B keeps one unit in stock so its read checks below are meaningful.
  perform public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null, '[{"quantity":1}]');
  perform pg_temp.yo();
  assert (select string_agg(id::text || status || coalesce(roll_id::text, '-'), ',' order by id)
          from public.film_units where owner_user_id = a) = a_before, 'B never moves A units';
  assert (select unit_price_minor from public.film_purchases where id = pur_a) = 20000, 'B never edits A purchases';

  -- Reads: each account sees exactly its own rows; pending and rejected none.
  -- Reads do not need the feature, so C still sees its own rows.
  foreach rel in array array[
    'public.film_purchases:owner_user_id', 'public.film_units:owner_user_id',
    'public.inventory_commands:owner_user_id', 'public.finance_preferences:user_id',
    'public.film_inventory_lines:owner_user_id', 'public.film_purchase_status:owner_user_id',
    'public.roll_film_origin:owner_user_id'
  ] loop
    tbl := split_part(rel, ':', 1);
    col := split_part(rel, ':', 2);
    foreach actor in array array[a, b, c, p, r] loop
      execute format('select count(*) from %s where %I = %L', tbl, col, actor) into raw;
      assert raw > 0, format('%s has data for %s, so a zero below means hidden', tbl, actor);
      perform pg_temp.como(actor);
      execute format('select count(*), count(*) filter (where %I <> %L) from %s', col, actor, tbl)
        into seen, foreign_seen;
      perform pg_temp.yo();
      assert foreign_seen = 0, format('%s: %s sees rows of others', tbl, actor);
      if actor in (p, r) then
        assert seen = 0, format('%s: blocked account %s sees %s rows', tbl, actor, seen);
      else
        assert seen = raw, format('%s: %s sees %s of its %s rows', tbl, actor, seen, raw);
      end if;
    end loop;
  end loop;
end $$;
