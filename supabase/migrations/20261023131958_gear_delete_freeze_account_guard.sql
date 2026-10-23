-- Equipo borrado: el congelado no escribe en una cuenta que se está borrando.
--
-- `rolls_freeze_gear()` solo se saltaba con la bandera de `delete_my_account`.
-- Borrar la cuenta por otro camino (el panel de Supabase, un `delete from
-- auth.users` a mano) no pone la bandera: la cascada borra la cámara cuando la
-- fila de `auth.users` ya no está, y el congelado todavía actualizaba los
-- rollos de esa cuenta. Si esos rollos se crearon en la misma transacción,
-- Postgres vuelve a revisar su llave a `auth.users` y el borrado falla con
-- 23503 (lo encontró la prueba del buzón en staging). Con filas ya confirmadas,
-- como en producción, no fallaba, pero escribía en rollos a punto de irse.
--
-- La misma guarda que tenía el disparador del buzón: si el dueño ya no existe,
-- no se escribe nada, por cualquier camino.

create or replace function app_private.rolls_freeze_gear()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- El mismo texto que arma rolls_flat, para que el rollo se vea igual.
  v_name text := nullif(btrim(concat_ws(' ', old.maker, old.model)), '');
begin
  -- El cierre de cuenta se lleva los rollos en la misma cascada, con o sin la
  -- bandera de delete_my_account. Y una pieza sin marca ni modelo no tiene
  -- nombre que conservar.
  if public.borrado_de_cuenta_en_curso()
     or not exists (select 1 from auth.users u where u.id = old.owner_user_id)
     or v_name is null then
    return old;
  end if;

  -- Solo rollos del mismo dueño: nunca copiar el nombre de un equipo ajeno.
  if tg_table_name = 'cameras' then
    update public.rolls
       set camera_snapshot = jsonb_build_object(
             'version', 1,
             'display_name', v_name,
             'maker', old.maker,
             'model', old.model,
             'format', old.format,
             'type', old.type,
             'mount', old.mount,
             'interchangeable', old.supports_interchangeable_lenses,
             'camera_id', old.id,
             'frozen_at', now())
     where camera_id = old.id and owner_user_id = old.owner_user_id;
  else
    update public.rolls
       set lens_snapshot = jsonb_build_object(
             'version', 1,
             'display_name', v_name,
             'maker', old.maker,
             'model', old.model,
             'mount', old.mount,
             'is_zoom', old.is_zoom,
             'focal_min', old.focal_min,
             'focal_max', old.focal_max,
             'max_aperture', old.max_aperture,
             'max_aperture_tele', old.max_aperture_tele,
             'lens_id', old.id,
             'frozen_at', now())
     where lens_id = old.id and owner_user_id = old.owner_user_id;
  end if;
  return old;
end;
$$;
revoke all on function app_private.rolls_freeze_gear() from public, anon, authenticated;
