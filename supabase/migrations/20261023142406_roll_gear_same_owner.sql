-- Un rollo solo apunta a una cámara y a un lente de su misma cuenta.
--
-- `rolls.camera_id` y `rolls.lens_id` solo tenían la llave a cameras y lenses:
-- cualquier cuenta podía guardar un rollo con el id de una cámara o un lente
-- ajenos. RLS no lo ve, porque la política de rolls revisa el dueño del rollo,
-- no el de su equipo. Los fotogramas (`preserve_exposure_lens`) y los
-- favoritos del perfil (`validate_profile_favorites`) ya lo exigían; los
-- rollos eran el hueco. Revisado el 23-oct-2026: ni producción ni staging
-- tienen un rollo así, así que no hay datos que corregir.
--
-- Vale para todos, también para las funciones del servidor: ninguna tiene
-- motivo para enlazar equipo ajeno. Corre antes de la llave, así que una pieza
-- que no existe responde igual que una ajena y no sirve para averiguar ids.
-- El `set null` de la llave al borrar equipo sigue pasando: deja la llave
-- vacía y el resto del equipo del rollo es del mismo dueño.

create function app_private.rolls_gear_same_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.camera_id is not null and not exists (
    select 1 from public.cameras c
    where c.id = new.camera_id and c.owner_user_id = new.owner_user_id
  ) then
    raise exception 'Camera must belong to the owner of the roll' using errcode = '23514';
  end if;
  if new.lens_id is not null and not exists (
    select 1 from public.lenses l
    where l.id = new.lens_id and l.owner_user_id = new.owner_user_id
  ) then
    raise exception 'Lens must belong to the owner of the roll' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function app_private.rolls_gear_same_owner() from public, anon, authenticated;

create trigger rolls_gear_same_owner
before insert or update of camera_id, lens_id, owner_user_id on public.rolls
for each row execute function app_private.rolls_gear_same_owner();
