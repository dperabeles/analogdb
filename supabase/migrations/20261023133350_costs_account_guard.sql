-- Costos (ANA-184): congelar no escribe nada de una cuenta que se está
-- borrando, la borre quien la borre.
--
-- costs_freeze_equipment y costs_freeze_roll solo se saltaban con
-- app.borrando_cuenta, que pone delete_my_account. Al borrar una cuenta desde
-- el panel de Supabase la bandera no está: la cascada borra la cámara o el
-- rollo cuando la fila de auth.users ya no existe, y el disparador actualizaba
-- gastos de esa cuenta. Con filas de una transacción anterior pasa, pero con
-- filas creadas en la misma transacción Postgres vuelve a revisar la llave y
-- el borrado falla (23503). Lo encontró la prueba del buzón; gear_delete_freeze
-- tenía el mismo hueco y ya lleva esta guarda.

create or replace function app_private.costs_freeze_equipment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.borrado_de_cuenta_en_curso()
     or not exists (select 1 from auth.users u where u.id = old.owner_user_id) then
    return old;
  end if;
  if tg_table_name = 'cameras' then
    update public.equipment_purchases
       set label = btrim(coalesce(old.maker, '') || ' ' || coalesce(old.model, '')), version = version + 1
     where camera_id = old.id and owner_user_id = old.owner_user_id;
  else
    update public.equipment_purchases
       set label = btrim(coalesce(old.maker, '') || ' ' || coalesce(old.model, '')), version = version + 1
     where lens_id = old.id and owner_user_id = old.owner_user_id;
  end if;
  return old;
end;
$$;

create or replace function app_private.costs_freeze_roll()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.borrado_de_cuenta_en_curso()
     or not exists (select 1 from auth.users u where u.id = old.owner_user_id) then
    return old;
  end if;
  update public.film_purchases
     set film_stock_id = old.film_stock_id, format = old.format, roll_code = old.code,
         version = version + 1
   where roll_id = old.id and origin = 'roll' and owner_user_id = old.owner_user_id;
  update public.lab_charges
     set lab_id = app_private.charge_lab(kind, old.dev_lab_id, old.scan_lab_id), roll_code = old.code,
         version = version + 1
   where roll_id = old.id and owner_user_id = old.owner_user_id;
  return old;
end;
$$;
