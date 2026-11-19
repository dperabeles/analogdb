-- Film inventory: «refrigerado» and «carga» on each unit, and editing a whole
-- line (20261119150000). Run inside BEGIN / ROLLBACK after
-- film_inventory_helpers.sql. Synthetic accounts only.
do $$
declare
  a uuid; b uuid;
  portra bigint; gold bigint; b_pending bigint; cam_a bigint;
  y2027 jsonb := '{"year":2027}';
  y2020 jsonb := '{"year":2020}';
  res jsonb; cmd uuid;
  pur_cold uuid; pur_plain uuid;
  roll_cold bigint; roll_plain bigint;
  n integer;
begin
  a := pg_temp.inv_user('flaga');
  b := pg_temp.inv_user('flagb');
  perform pg_temp.inv_member(a);
  perform pg_temp.inv_member(b);
  -- Catalog films, approved: anyone may stock them.
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Prueba Flag', 'Portra Flag', 400, 'COLOR', false, 'approved') returning id into portra;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Prueba Flag', 'Gold Flag', 200, 'COLOR', false, 'approved') returning id into gold;
  insert into public.cameras (owner_user_id, maker, model, format)
  values (a, 'Prueba Flag', 'Cam', '35mm') returning id into cam_a;

  perform pg_temp.como(b);
  -- B's own suggestion: private to B until reviewed.
  b_pending := public.ensure_film_stock('Prueba Flag', 'Solo de B', 100, 'B/W');
  perform pg_temp.yo();

  perform pg_temp.como(a);
  perform public.set_default_currency('MXN');

  -- ── Receive: each group may carry its flags; they split the line ──
  res := public.inventory_receive(gen_random_uuid(), portra, 35, 15000, 'MXN', null,
    format('[{"quantity":2,"expiration_date":%s,"refrigerated":true},
             {"quantity":3,"expiration_date":%s}]', y2020, y2020)::jsonb);
  pur_cold := (res ->> 'purchase_id')::uuid;
  assert (select count(*) from public.film_inventory_lines
          where owner_user_id = a and film_stock_id = portra) = 2,
    'refrigerated and plain units of the same date are two lines';
  assert (select available from public.film_inventory_lines
          where owner_user_id = a and film_stock_id = portra and refrigerated) = 2,
    'the refrigerated line has its two units';
  assert (select prices -> 0 ->> 'units' from public.film_inventory_lines
          where owner_user_id = a and film_stock_id = portra and refrigerated)::int = 2,
    'prices are summed per line, flags included';
  perform pg_temp.espera_error(format(
    'select public.inventory_receive(gen_random_uuid(), %s, 35, null, null, null, %L)',
    portra, '[{"quantity":1,"refrigerated":"si"}]'), 'P1103');

  -- ── Old clients: a call without flags only sees the plain line ──
  perform pg_temp.espera_error(format(
    'select public.inventory_adjust(gen_random_uuid(), %s, 35, %L, null, 5, 4)', portra, y2020),
    'P1105');
  perform public.inventory_adjust(gen_random_uuid(), portra, 35, y2020, null, 3, 3);
  perform public.inventory_adjust(gen_random_uuid(), portra, 35, y2020, null, 2, 2, true, false);
  -- Units found in a flagged line keep its flags.
  perform public.inventory_adjust(gen_random_uuid(), portra, 35, y2020, null, 2, 3, true, false);
  assert (select count(*) from public.film_units
          where owner_user_id = a and refrigerated and status = 'available') = 3,
    'a found unit joins the refrigerated line as refrigerated';
  perform public.inventory_adjust(gen_random_uuid(), portra, 35, y2020, null, 3, 2, true, false);

  -- ── Load: the roll inherits the unit's flags ──
  res := public.inventory_load(gen_random_uuid(), portra, 35, y2020, null, current_date,
                               cam_a, null, 36, null, null, true, false);
  roll_cold := (res ->> 'roll_id')::bigint;
  assert (select film_refrigerated and not film_respooled and not fresh
          from public.rolls where id = roll_cold),
    'a roll loaded from the refrigerated line is refrigerated, and expired';
  res := public.inventory_load(gen_random_uuid(), portra, 35, y2020, null, current_date,
                               cam_a, null, 36, null);
  roll_plain := (res ->> 'roll_id')::bigint;
  assert (select not film_refrigerated from public.rolls where id = roll_plain),
    'an old-style load takes a plain unit';

  -- ── Swap: the roll follows its new unit's flags ──
  perform public.inventory_swap(gen_random_uuid(), roll_plain, portra, 35, y2020, null, true, false);
  assert (select film_refrigerated from public.rolls where id = roll_plain),
    'swapping into the refrigerated line makes the roll refrigerated';
  perform public.inventory_swap(gen_random_uuid(), roll_plain, portra, 35, y2020, null);
  assert (select not film_refrigerated from public.rolls where id = roll_plain),
    'and back';

  -- ── Edit a line ──
  -- Stale count: the person saw 5 but the plain line has 2 now.
  perform pg_temp.espera_error(format(
    'select public.inventory_edit_line(gen_random_uuid(), %s, 35, %L, null, false, false, 5, %s, %L, null, true, true)',
    portra, y2020, portra, y2027), 'P1105');
  -- Missing flags are not «false»: refused.
  perform pg_temp.espera_error(format(
    'select public.inventory_edit_line(gen_random_uuid(), %s, 35, %L, null, false, false, 2, %s, %L, null, null, false)',
    portra, y2020, portra, y2027), 'P1103');
  -- Another account's private film is not a film this account can choose.
  perform pg_temp.espera_error(format(
    'select public.inventory_edit_line(gen_random_uuid(), %s, 35, %L, null, false, false, 2, %s, %L, null, false, false)',
    portra, y2020, b_pending, y2020), 'P1103');
  -- Its purchase has a loaded roll and a refrigerated line: the film is in use.
  perform pg_temp.espera_error(format(
    'select public.inventory_edit_line(gen_random_uuid(), %s, 35, %L, null, false, false, 2, %s, %L, null, false, false)',
    portra, y2020, gold, y2020), 'P1112');
  assert (select film_stock_id from public.film_purchases where id = pur_cold) = portra,
    'a refused film change leaves the purchase';

  -- Date and flags: the plain 2020 units become refrigerated, respooled 2027.
  cmd := gen_random_uuid();
  res := public.inventory_edit_line(cmd, portra, 35, y2020, null, false, false, 2,
                                    portra, y2027, null, true, true);
  assert (res ->> 'units')::int = 2, 'two units edited';
  assert public.inventory_edit_line(cmd, portra, 35, y2020, null, false, false, 2,
                                    portra, y2027, null, true, true) = res,
    'a retry of the same command answers the same, without editing twice';
  assert (select available from public.film_inventory_lines
          where owner_user_id = a and film_stock_id = portra
            and expiration_date = y2027 and refrigerated and respooled) = 2,
    'the edited units form their own line';
  assert not exists (select 1 from public.film_inventory_lines
                     where owner_user_id = a and film_stock_id = portra
                       and expiration_date = y2020 and not refrigerated),
    'the old line is gone';

  -- Editing into an existing line merges with it.
  perform public.inventory_edit_line(gen_random_uuid(), portra, 35, y2027, null, true, true, 2,
                                     portra, y2020, null, true, false);
  assert (select available from public.film_inventory_lines
          where owner_user_id = a and film_stock_id = portra
            and expiration_date = y2020 and refrigerated and not respooled) = 3,
    'two edited units join the line of one';

  -- Without a date: the declaration is kept; a date then wins.
  perform public.inventory_receive(gen_random_uuid(), gold, 35, 9000, 'MXN', null,
    '[{"quantity":2,"declared_fresh":false}]');
  select id into pur_plain from public.film_purchases
  where owner_user_id = a and film_stock_id = gold;
  perform public.inventory_edit_line(gen_random_uuid(), gold, 35, null, false, false, false, 2,
                                     gold, y2027, null, false, false);
  assert (select bool_and(expiration_date = y2027 and declared_fresh)
          from public.film_units where purchase_id = pur_plain),
    'a date added later replaces the declared condition';

  -- A whole purchase in the line: the film changes, and so does the purchase.
  perform public.inventory_edit_line(gen_random_uuid(), gold, 35, y2027, null, false, false, 2,
                                     portra, y2027, null, false, false);
  assert (select film_stock_id from public.film_purchases where id = pur_plain) = portra,
    'the purchase follows its units to the right film';
  assert (select version from public.film_purchases where id = pur_plain) = 2,
    'the purchase version moves, so a stale purchase edit conflicts';
  assert not exists (select 1 from public.film_units where purchase_id = pur_plain and film_stock_id = gold),
    'no unit is left on the wrong film';
  perform pg_temp.yo();

  -- ── Isolation: B cannot edit A's lines, and A's units never move ──
  n := (select count(*) from public.film_units where owner_user_id = a and status = 'available'
          and film_stock_id = portra and expiration_date = y2027);
  perform pg_temp.como(b);
  perform pg_temp.espera_error(format(
    'select public.inventory_edit_line(gen_random_uuid(), %s, 35, %L, null, false, false, %s, %s, %L, null, true, true)',
    portra, y2027, n, portra, y2020), 'P1105');
  assert (select count(*) from public.rolls where film_refrigerated) = 0,
    'B sees none of A''s rolls, flagged or not';
  perform pg_temp.yo();
  assert (select count(*) from public.film_units where owner_user_id = a and status = 'available'
            and film_stock_id = portra and expiration_date = y2027 and not refrigerated) = n,
    'B never edits A units';
end $$;

-- The roll's sheet reads rolls_flat: a loaded roll shows its flags there,
-- only to its owner.
do $$
declare
  a uuid; b uuid; portra bigint; cam bigint; roll bigint;
begin
  a := pg_temp.inv_user('flata');
  b := pg_temp.inv_user('flatb');
  perform pg_temp.inv_member(a);
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Prueba Flat', 'Verita Flat', 200, 'COLOR', false, 'approved') returning id into portra;
  insert into public.cameras (owner_user_id, maker, model, format)
  values (a, 'Prueba Flat', 'Cam', '35mm') returning id into cam;
  perform pg_temp.como(a);
  perform public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null,
    '[{"quantity":1,"refrigerated":true,"respooled":true}]');
  roll := (public.inventory_load(gen_random_uuid(), portra, 35, null, true, current_date,
                                 cam, null, 36, null, null, true, true) ->> 'roll_id')::bigint;
  assert (select "FILM REFRIGERATED" and "FILM RESPOOLED" from public.rolls_flat where id = roll),
    'the roll sheet reads both flags';
  perform pg_temp.yo();
  perform pg_temp.como(b);
  assert not exists (select 1 from public.rolls_flat where id = roll), 'B never reads A''s roll';
  perform pg_temp.yo();
end $$;
