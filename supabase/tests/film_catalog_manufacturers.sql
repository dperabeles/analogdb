-- Film catalog base (20261119200000): manufacturers, process, moderation with
-- edit / merge / undo, and lab edits. Run inside BEGIN / ROLLBACK after
-- film_inventory_helpers.sql. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; p uuid; adm uuid;
  approved_maker bigint; a_maker bigint; b_maker bigint; fuji bigint; fujifilm bigint;
  portra bigint; a_film bigint; a_film2 bigint; x bigint;
  roll1 bigint; roll2 bigint; unit1 uuid; purchase1 uuid;
  change bigint; preview jsonb; lab bigint;
  n bigint;
begin
  assert app_private.manufacturer_key('Lucky Film') = app_private.manufacturer_key('Luckyfilm'),
    'spacing does not make another manufacturer';
  assert app_private.manufacturer_key('Ferranía') = app_private.manufacturer_key('FERRANIA'),
    'accents and case do not either';

  a := pg_temp.inv_user('cata');
  b := pg_temp.inv_user('catb');
  p := pg_temp.inv_user('catp', 'pending');
  adm := pg_temp.inv_user('catadm');
  update public.user_roles set role = 'admin' where user_id = adm;

  -- A catalog film inserted as migrations do: its manufacturer is created
  -- approved, and the text follows it.
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Prueba Marca', 'Portra Cat', 400, 'COLOR', false, 'approved') returning id into portra;
  select manufacturer_id into approved_maker from public.film_stocks where id = portra;
  assert (select status from public.manufacturers where id = approved_maker) = 'approved',
    'a catalog film brings its manufacturer approved';

  -- ── The old path, by text (the web) ──
  perform pg_temp.como(a);
  x := public.ensure_film_stock('prueba  MARCA', 'Portra Cat');
  assert x = portra, 'another spelling of an approved manufacturer finds the approved film';
  a_film := public.ensure_film_stock('Marca Nueva A', 'Film A', 200, 'COLOR');
  select manufacturer_id into a_maker from public.film_stocks where id = a_film;
  assert (select status = 'pending' and created_by = a from public.manufacturers where id = a_maker),
    'a new brand typed by A is A''s pending manufacturer';
  perform pg_temp.yo();

  -- ── Isolation: B never sees A's proposal; B proposing the same name gets
  -- B's own, so nothing reveals that A wrote it ──
  perform pg_temp.como(b);
  assert not exists (select 1 from public.manufacturers where id = a_maker), 'B cannot read A''s proposal';
  assert not exists (select 1 from public.film_stocks where id = a_film), 'nor A''s film';
  b_maker := public.propose_manufacturer('marca nueva a');
  assert b_maker <> a_maker, 'B gets its own pending manufacturer';
  assert public.propose_manufacturer('Prueba Marca') = approved_maker, 'an approved one is shared';
  perform pg_temp.espera_error(format(
    'select public.propose_film_stock(%s, %L)', a_maker, 'Robado'), 'P1103');
  assert (select count(*) from public.catalog_changes) = 0, 'B reads no catalog log';
  perform pg_temp.yo();

  -- Proposing needs an approved account, and a session.
  perform pg_temp.como(p);
  perform pg_temp.espera_error('select public.propose_manufacturer(''Cualquiera'')', 'P1202');
  perform pg_temp.yo();
  perform pg_temp.como(null);
  perform pg_temp.espera_error('select public.propose_manufacturer(''Cualquiera'')', '42501');
  perform pg_temp.yo();

  -- ── Proposing a whole film ──
  perform pg_temp.como(a);
  a_film2 := public.propose_film_stock(a_maker, 'Film A2', 800, 'COLOR', 'ECN-2');
  assert (select process = 'ECN-2' and status = 'pending' and created_by = a and manufacturer = 'Marca Nueva A'
          from public.film_stocks where id = a_film2), 'a proposed film keeps its process and maker';
  assert public.propose_film_stock(approved_maker, 'portra   cat') = portra,
    'an existing approved film is found, not copied';
  perform pg_temp.espera_error(format(
    'select public.propose_film_stock(%s, %L, null, null, %L)', a_maker, 'Film X', 'XPRO'), 'P1103');
  perform pg_temp.yo();

  -- ── Only the administrator moderates ──
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format(
    'select public.admin_film_stock_update(%s, %s, %L, null, null, null)', portra, approved_maker, 'Hack'), 'P1205');
  perform pg_temp.espera_error(format('select public.admin_film_stock_merge(%s, %s)', a_film, portra), 'P1205');
  perform pg_temp.espera_error(format('select public.admin_film_stock_merge_preview(%s, %s)', a_film, portra), 'P1205');
  perform pg_temp.espera_error('select public.admin_film_stock_undo_merge(1)', 'P1205');
  perform pg_temp.espera_error(format('select public.admin_manufacturer_review(%s, %L)', a_maker, 'approved'), 'P1205');
  perform pg_temp.espera_error(format('select public.admin_manufacturer_update(%s, %L)', approved_maker, 'Hack'), 'P1205');
  perform pg_temp.espera_error(format('select public.admin_manufacturer_merge(%s, %s)', a_maker, approved_maker), 'P1205');
  perform pg_temp.espera_error('select public.admin_manufacturer_undo_merge(1)', 'P1205');
  perform pg_temp.espera_error('select public.admin_lab_update(1, ''{"name":"x"}'')', 'P1205');
  perform pg_temp.yo();
  assert (select name from public.film_stocks where id = portra) = 'Portra Cat', 'nothing moved';

  -- ── Edit, with its log ──
  perform pg_temp.como(adm);
  change := public.admin_film_stock_update(a_film, a_maker, 'Film A corregido', 160, 'COLOR', 'C-41');
  perform pg_temp.yo();
  assert (select name = 'Film A corregido' and iso = 160 and process = 'C-41'
          from public.film_stocks where id = a_film), 'the pending film is corrected';
  assert (select before ->> 'name' = 'Film A' and after ->> 'name' = 'Film A corregido' and changed_by = adm
          from public.catalog_changes where id = change), 'and logged with before and after';
  -- An approved film cannot take another approved film's name.
  insert into public.film_stocks (manufacturer, name, in_catalog, status)
  values ('Prueba Marca', 'Gold Cat', false, 'approved') returning id into x;
  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format(
    'select public.admin_film_stock_update(%s, %s, %L, null, null, null)', x, approved_maker, 'portra cat'), 'P1113');
  perform pg_temp.yo();

  -- ── Merge «Film A corregido» (A's) into Portra Cat, and undo ──
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id)
  values (a, 'R980', gen_random_uuid(), a_film) returning id into roll1;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id)
  values (a, 'R981', gen_random_uuid(), a_film) returning id into roll2;
  insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity)
  values (a, a_film, 35, 1) returning id into purchase1;
  insert into public.film_units (owner_user_id, purchase_id, film_stock_id, format)
  values (a, purchase1, a_film, 35) returning id into unit1;

  perform pg_temp.como(adm);
  preview := public.admin_film_stock_merge_preview(a_film, portra);
  assert (preview ->> 'rolls')::int = 2 and (preview ->> 'units')::int = 1
     and (preview ->> 'accounts')::int = 1, 'the preview counts what moves';
  perform pg_temp.espera_error(format('select public.admin_film_stock_merge(%s, %s)', portra, a_film2), 'P1114');
  change := public.admin_film_stock_merge(a_film, portra);
  perform pg_temp.yo();
  assert (select status = 'merged' and merged_into = portra from public.film_stocks where id = a_film),
    'the copy is merged';
  assert (select count(*) from public.rolls where id in (roll1, roll2) and film_stock_id = portra) = 2,
    'its rolls are on the catalog film';
  assert (select film_stock_id from public.film_units where id = unit1) = portra, 'and its unit';
  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format('select public.admin_film_stock_merge(%s, %s)', a_film, portra), 'P1114');
  perform pg_temp.yo();

  -- A changed one roll afterwards: undo leaves that one alone.
  update public.rolls set film_stock_id = x where id = roll2;
  perform pg_temp.como(adm);
  perform public.admin_film_stock_undo_merge(change);
  perform pg_temp.espera_error(format('select public.admin_film_stock_undo_merge(%s)', change), 'P1114');
  perform pg_temp.yo();
  assert (select status = 'pending' and merged_into is null from public.film_stocks where id = a_film),
    'undo brings the film back as it was';
  assert (select film_stock_id from public.rolls where id = roll1) = a_film, 'and its roll';
  assert (select film_stock_id from public.rolls where id = roll2) = x, 'but not the roll A changed since';
  assert (select film_stock_id from public.film_units where id = unit1) = a_film, 'and its unit';
  perform pg_temp.como(a);
  assert exists (select 1 from public.film_stocks where id = a_film), 'A sees its film again';
  perform pg_temp.yo();

  -- ── Manufacturers: review, rename, merge and undo ──
  insert into public.manufacturers (name, status, reviewed_at) values ('Fujifilm Cat', 'approved', now())
  returning id into fujifilm;
  perform pg_temp.como(a);
  fuji := public.propose_manufacturer('Fuji Cat');
  x := public.propose_film_stock(fuji, 'Superia Cat');
  perform pg_temp.yo();
  perform pg_temp.como(adm);
  change := public.admin_manufacturer_merge(fuji, fujifilm);
  perform pg_temp.yo();
  assert (select manufacturer = 'Fujifilm Cat' and manufacturer_id = fujifilm from public.film_stocks where id = x),
    'its films take the right maker and its name';
  perform pg_temp.como(adm);
  perform public.admin_manufacturer_undo_merge(change);
  perform pg_temp.yo();
  assert (select manufacturer = 'Fuji Cat' and manufacturer_id = fuji from public.film_stocks where id = x),
    'and undo gives them back';
  assert (select status from public.manufacturers where id = fuji) = 'pending', 'pending again';

  -- Approving a proposal whose key already exists merges it.
  perform pg_temp.como(b);
  perform public.propose_film_stock(b_maker, 'Film B');
  perform pg_temp.yo();
  perform pg_temp.como(adm);
  perform public.admin_manufacturer_review(a_maker, 'approved');
  change := public.admin_manufacturer_review(b_maker, 'approved');
  perform pg_temp.yo();
  assert change is not null and (select status from public.manufacturers where id = b_maker) = 'merged',
    'the second approval of one name merges into the first';
  assert not exists (select 1 from public.film_stocks where manufacturer_id = b_maker), 'with its films';

  -- Renaming an approved one renames the text of its films.
  perform pg_temp.como(adm);
  perform public.admin_manufacturer_update(approved_maker, 'Prueba Marca Correcta');
  perform pg_temp.espera_error(format('select public.admin_manufacturer_update(%s, %L)', a_maker, 'prueba marca correcta'), 'P1113');
  perform pg_temp.yo();
  assert (select manufacturer from public.film_stocks where id = portra) = 'Prueba Marca Correcta',
    'films follow their manufacturer';

  -- ── Labs: an approved one is edited, and logged ──
  insert into public.labs (name, city, country, status) values ('Lab Cat', 'Monterrey', 'México', 'approved')
  returning id into lab;
  update public.labs set status = 'approved' where id = lab;
  perform pg_temp.como(adm);
  change := public.admin_lab_update(lab, '{"name":"Lab Cat Centro","formats":["35mm","120"],"accepts_mail":true}');
  perform pg_temp.espera_error(format('select public.admin_lab_update(%s, %L)', lab, '{"status":"rejected"}'), 'P1103');
  perform pg_temp.espera_error(format('select public.admin_lab_update(%s, %L)', lab, '{"name":"  "}'), 'P1103');
  perform pg_temp.espera_error(format('select public.admin_lab_update(%s, %L)', lab, '{"formats":["35"]}'), 'P1103');
  perform pg_temp.yo();
  assert (select name = 'Lab Cat Centro' and formats = array['35mm','120'] and accepts_mail
                 and status = 'approved' from public.labs where id = lab), 'the lab is edited, still approved';
  assert (select before ->> 'name' = 'Lab Cat' from public.catalog_changes where id = change), 'and logged';

  -- Every film still has a manufacturer, and its text is that name.
  select count(*) into n from public.film_stocks f
   left join public.manufacturers m on m.id = f.manufacturer_id
   where m.id is null or f.manufacturer is distinct from m.name;
  assert n = 0, format('%s films disagree with their manufacturer', n);
end $$;
