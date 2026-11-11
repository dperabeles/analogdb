-- Deleting an account from the dashboard (without app.borrando_cuenta), with
-- gear, purchases, a priced roll and a lab charge created in the same
-- transaction: the freeze triggers write nothing for an account being deleted.
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql. Synthetic
-- accounts only.
do $$
declare
  c uuid := pg_temp.inv_user('cgc');
  d uuid := pg_temp.inv_user('cgd');
  who uuid; cam bigint; lens bigint; r bigint; portra bigint;
begin
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Portra Guard', 400, 'COLOR', false) returning id into portra;
  foreach who in array array[c, d] loop
    insert into public.cameras (owner_user_id, maker, model, format)
    values (who, 'Prueba Cost', 'Cam Guard', '35mm') returning id into cam;
    insert into public.lenses (owner_user_id, maker, model, mount)
    values (who, 'Prueba Cost', 'Lente Guard', 'M') returning id into lens;
    insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, camera_id, lens_id)
    values (who, 'R961', gen_random_uuid(), portra, 35, 'Developed', cam, lens) returning id into r;
    insert into public.equipment_purchases (owner_user_id, kind, camera_id, amount_minor, currency)
    values (who, 'camera', cam, 1000, 'MXN');
    insert into public.equipment_purchases (owner_user_id, kind, lens_id, amount_minor, currency)
    values (who, 'lens', lens, 500, 'MXN');
    insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, origin, roll_id)
    values (who, portra, 35, 1, 100, 'MXN', 'roll', r);
    insert into public.lab_charges (owner_user_id, roll_id, kind, amount_minor, currency)
    values (who, r, 'dev_scan', 300, 'MXN');
  end loop;

  -- From the app: delete_my_account turns app.borrando_cuenta on.
  perform pg_temp.como(c);
  perform public.delete_my_account();
  perform pg_temp.yo();

  -- From the dashboard: no flag. delete_my_account left it on, so turn it off.
  perform set_config('app.borrando_cuenta', '', true);
  delete from auth.users where id = d;

  assert not exists (select 1 from auth.users where id in (c, d)), 'both accounts deleted';
  assert not exists (select 1 from public.equipment_purchases where owner_user_id in (c, d)), 'equipment purchases gone';
  assert not exists (select 1 from public.film_purchases where owner_user_id in (c, d)), 'film purchases gone';
  assert not exists (select 1 from public.lab_charges where owner_user_id in (c, d)), 'lab charges gone';
  assert not exists (select 1 from public.deleted_rows where dueno in (c, d)), 'trash emptied with both accounts';
end $$;
