-- Film catalog, Fase 2d (20261120090000): the ECN-2/C-41 process, the new
-- films, and a merge done by a migration that the panel can undo. Run inside
-- BEGIN / ROLLBACK after film_inventory_helpers.sql and before any other suite
-- (they add approved films of their own). Synthetic accounts only.
do $$
declare
  a uuid; adm uuid;
  maker bigint; dup bigint;
  n bigint;
begin
  a := pg_temp.inv_user('proca');
  adm := pg_temp.inv_user('procadm');
  update public.user_roles set role = 'admin' where user_id = adm;

  -- ── The new films, everywhere the migration runs ──
  select count(*) into n from public.film_stocks f
   where f.status = 'approved' and f.in_catalog and f.created_by is null
     and (app_private.film_stock_key(f.manufacturer, f.name), f.process, f.iso) in (
       (app_private.film_stock_key('Kodak', 'Ektapan P3200'), 'BW', 3200),
       (app_private.film_stock_key('Kodak', 'Ektacolor Pro 400'), 'C-41', 400),
       (app_private.film_stock_key('Kodak', 'Vision3 500T AHU'), 'ECN-2/C-41', 500),
       (app_private.film_stock_key('Reflx Lab', '100D'), 'ECN-2/C-41', 100),
       (app_private.film_stock_key('Reflx Lab', '100R'), 'E-6', 100),
       (app_private.film_stock_key('Reflx Lab', 'Double X'), 'BW', 250));
  assert n = 6, format('the new films are in the catalog with their process (%s of 6)', n);
  assert (select count(*) from public.film_stocks where manufacturer = 'Reflx Lab' and status = 'approved') = 13,
    'the whole Reflx Lab line';
  assert (select status from public.manufacturers m
           where app_private.manufacturer_key(m.name) = app_private.manufacturer_key('Reflx Lab')) = 'approved',
    'Reflx Lab is an approved manufacturer';
  assert not exists (select 1 from public.film_stocks
                      where status = 'approved' and process is not null
                        and not app_private.film_process_ok(process)),
    'every process is a valid one';

  -- In production the cleanup happened.
  if exists (select 1 from public.film_stocks where id = 62 and name = 'Double-X') then
    assert not exists (select 1 from public.film_stocks where status = 'approved'
                        and app_private.film_stock_key(manufacturer, name)
                            in (app_private.film_stock_key('Kodak', 'Double X'),
                                app_private.film_stock_key('Kodak', 'Gallostill 800T'),
                                app_private.film_stock_key('Kodak', 'Gallostill 400D'))),
      'the duplicates and Gallostill under Kodak are gone';
    assert (select iso from public.film_stocks where id = 61) = 3200, 'T-MAX P3200 is 3200';
    assert (select count(*) from public.catalog_changes where changed_by is null and undone_at is null) >= 4,
      'each cleanup is in the log';
    assert (select count(*) from public.film_stocks where status = 'approved' and process is null
              and btrim(coalesce(name, '')) <> '') <= 1,
      'every named approved film has a process (Kodak Ultra waits for Diego)';
  end if;

  -- ── The process the server accepts ──
  perform pg_temp.como(a);
  maker := public.propose_manufacturer('Proc Marca');
  dup := public.propose_film_stock(maker, 'Proc 800T', 800, 'COLOR', 'ECN-2/C-41');
  assert (select process from public.film_stocks where id = dup) = 'ECN-2/C-41',
    'a user proposes a film that develops both ways';
  perform pg_temp.espera_error(format(
    'select public.propose_film_stock(%s, %L, null, null, %L)', maker, 'Proc X', 'ECN2/C41'), 'P1103');
  perform pg_temp.yo();
  perform pg_temp.espera_error(
    'insert into public.film_stocks (manufacturer, name, status, process) values (''Proc Marca'', ''Proc Y'', ''approved'', ''C41'')',
    '23514');

  perform pg_temp.como(adm);
  perform public.admin_film_stock_update(dup, maker, 'Proc 800T', 800, 'COLOR', 'C-41');
  assert (select process from public.film_stocks where id = dup) = 'C-41', 'the panel edits it';
  perform public.admin_film_stock_update(dup, maker, 'Proc 800T', 800, 'COLOR', 'ECN-2/C-41');
  assert (select process from public.film_stocks where id = dup) = 'ECN-2/C-41', 'and back';
  perform pg_temp.yo();

end $$;
