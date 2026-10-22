-- Film inventory: add film, correct available units, edit and void purchases.
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; c uuid;
  portra bigint;
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); c3 uuid := gen_random_uuid();
  res jsonb; res2 jsonb;
  pur uuid; pur_jpy uuid; pur_used uuid;
  feb jsonb := '{"year":2027,"month":2}';
  groups jsonb := '[{"quantity":3,"expiration_date":{"year":2027,"month":2}},
                    {"quantity":2,"expiration_date":{"year":2027,"month":5}}]';
  v integer;
begin
  a := pg_temp.inv_user('reca');
  b := pg_temp.inv_user('recb');
  c := pg_temp.inv_user('recc');
  perform pg_temp.inv_member(a);
  perform pg_temp.inv_member(b);
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Inv', 'Portra Inv', 400, 'COLOR', false) returning id into portra;

  perform pg_temp.como(a);
  -- One add with two expirations: one purchase, two lines.
  res := public.inventory_receive(c1, portra, 35, 20000, 'MXN', '2026-10-01', groups);
  pur := (res ->> 'purchase_id')::uuid;
  assert (res ->> 'units')::integer = 5, 'five units reported';
  assert (select quantity from public.film_purchases where id = pur) = 5, 'purchase holds the total';
  assert (select count(*) from public.film_units where purchase_id = pur and status = 'available') = 5, 'five units available';
  assert (select count(*) from public.film_inventory_lines) = 2, 'two lines by expiration';
  assert (select available from public.film_inventory_lines where expiration_date = feb) = 3, 'three in February';

  -- Same command and request replays; a different request conflicts.
  res2 := public.inventory_receive(c1, portra, 35, 20000, 'MXN', '2026-10-01', groups);
  assert res2 = res, 'replay returns the same receipt';
  assert (select count(*) from public.film_units) = 5, 'replay adds nothing';
  perform pg_temp.espera_error(format(
    'select public.inventory_receive(%L, %s, 35, 20000, %L, %L, %L)', c1, portra, 'MXN', '2026-10-01',
    '[{"quantity":4}]'), 'P1106');

  -- Price is optional; zero is a price; each currency keeps its own precision.
  res := public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null, '[{"quantity":1}]');
  assert (select unit_price_minor from public.film_purchases where id = (res ->> 'purchase_id')::uuid) is null, 'unknown price';
  res := public.inventory_receive(gen_random_uuid(), portra, 35, 0, 'MXN', null, '[{"quantity":1}]');
  assert (select unit_price_minor from public.film_purchases where id = (res ->> 'purchase_id')::uuid) = 0, 'explicit zero';
  res := public.inventory_receive(gen_random_uuid(), portra, 120, 1500, 'JPY', null, '[{"quantity":2}]');
  pur_jpy := (res ->> 'purchase_id')::uuid;
  -- Undated units keep their declaration.
  res := public.inventory_receive(gen_random_uuid(), portra, 35, null, null, null,
                                  '[{"quantity":1,"declared_fresh":false}]');
  assert (select declared_fresh from public.film_units where purchase_id = (res ->> 'purchase_id')::uuid) = false,
         'undated expired declaration kept';

  -- Invalid input changes nothing.
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, 100, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":1}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, %L, null, %L)',
    gen_random_uuid(), portra, 'MXN', '[{"quantity":1}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, 100, %L, null, %L)',
    gen_random_uuid(), portra, 'ZZZ', '[{"quantity":1}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 8, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":1}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":9999},{"quantity":1}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":0}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":1e20}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, current_date + 5, %L)',
    gen_random_uuid(), portra, '[{"quantity":1}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, -1, 35, null, null, null, %L)',
    gen_random_uuid(), '[{"quantity":1}]'), 'P1103');
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":1,"expiration_date":{"year":2027,"month":13}}]'), 'P1103');
  assert (select count(*) from public.film_purchases) = 5, 'failed adds left no purchase';

  -- Correct the February line (3 available).
  perform pg_temp.espera_error(format('select public.inventory_adjust(%L, %s, 35, %L, null, 2, 1)',
    c2, portra, feb), 'P1105');
  res := public.inventory_adjust(c2, portra, 35, feb, null, 3, 1);
  assert (res ->> 'available')::integer = 1, 'lowered to one';
  assert (select count(*) from public.film_units where purchase_id = pur and status = 'removed') = 2, 'two removed';
  assert (select quantity from public.film_purchases where id = pur) = 5, 'purchase untouched';
  res := public.inventory_adjust(c3, portra, 35, feb, null, 1, 4);
  assert (select count(*) from public.film_units where purchase_id is null) = 3, 'raised with units without purchase';
  assert public.inventory_adjust(c3, portra, 35, feb, null, 1, 4) = res, 'adjust replays';
  assert (select count(*) from public.film_units where purchase_id is null) = 3, 'replay adds nothing';
  assert (select available from public.film_inventory_lines where expiration_date = feb) = 4, 'line shows four';

  -- Edit a purchase: optimistic version; the owner only.
  v := (select version from public.film_purchases where id = pur);
  -- c1 already belongs to the receive above: another kind conflicts.
  perform pg_temp.espera_error(format('select public.inventory_update_purchase(%L, %L, %s, 21000, %L, %L)',
    c1, pur, v, 'MXN', '2026-10-02'), 'P1106');
  c1 := gen_random_uuid();
  res := public.inventory_update_purchase(c1, pur, v, 21000, 'MXN', '2026-10-02');
  assert (res ->> 'version')::integer = v + 1, 'version goes up';
  assert (select unit_price_minor from public.film_purchases where id = pur) = 21000, 'price corrected';
  assert public.inventory_update_purchase(c1, pur, v, 21000, 'MXN', '2026-10-02') = res, 'edit replays';
  perform pg_temp.espera_error(format('select public.inventory_update_purchase(%L, %L, %s, 22000, %L, null)',
    gen_random_uuid(), pur, v, 'MXN'), 'P1105');
  perform pg_temp.yo();

  perform pg_temp.como(b);
  perform pg_temp.espera_error(format('select public.inventory_update_purchase(%L, %L, %s, 1, %L, null)',
    gen_random_uuid(), pur, v + 1, 'MXN'), 'P1109');
  perform pg_temp.espera_error(format('select public.inventory_void_purchase(%L, %L, %s)',
    gen_random_uuid(), pur, v + 1), 'P1109');
  perform pg_temp.yo();

  -- Void: only while none of its units is loaded.
  perform pg_temp.como(a);
  res := public.inventory_void_purchase(gen_random_uuid(), pur_jpy, 1);
  assert (res ->> 'removed')::integer = 2, 'available units removed';
  assert (select voided_at from public.film_purchases where id = pur_jpy) is not null, 'purchase voided';
  perform pg_temp.espera_error(format('select public.inventory_update_purchase(%L, %L, 2, 1, %L, null)',
    gen_random_uuid(), pur_jpy, 'JPY'), 'P1103');
  perform pg_temp.yo();
  res := null;
  select id into pur_used from public.film_purchases where owner_user_id = a and unit_price_minor = 0;
  update public.film_units set status = 'loaded', loaded_on = current_date where purchase_id = pur_used;
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.inventory_void_purchase(%L, %L, 1)',
    gen_random_uuid(), pur_used), 'P1108');
  perform pg_temp.yo();

  -- Who may write.
  perform pg_temp.como(c);
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":1}]'), 'P1102');
  perform pg_temp.yo();
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  execute 'set local role authenticated';
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":1}]'), 'P1101');
  perform pg_temp.yo();
  perform pg_temp.como(null);
  perform pg_temp.espera_error(format('select public.inventory_receive(%L, %s, 35, null, null, null, %L)',
    gen_random_uuid(), portra, '[{"quantity":1}]'), '42501');
  perform pg_temp.yo();

  -- Balance: every purchase keeps exactly the units it bought; a voided one
  -- has none available.
  assert not exists (
    select 1 from public.film_purchases p
    where p.owner_user_id = a
      and (select count(*) from public.film_units u where u.purchase_id = p.id) <> p.quantity
  ), 'each purchase has its units';
  assert not exists (
    select 1 from public.film_units u join public.film_purchases p on p.id = u.purchase_id
    where p.voided_at is not null and u.status = 'available'
  ), 'voided purchases have nothing available';
end $$;
