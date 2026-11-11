-- Buzón privado (ANA-185): dos disparadores que el buzón necesita.
--
-- 1. La fecha de Por revelar. Hasta hoy solo la escribía el cambio rápido de
--    estado de la app; Editar Film y la web podían pasar un rollo a
--    To Develop sin ella. Ahora se fija con la hora del servidor cada vez que
--    el estado entra a To Develop, y volver a entrar reinicia la cuenta.
--
-- 2. El equipo borrado. Al borrar una cámara o un lente, la llave foránea deja
--    vacíos sus rollos. Antes de eso se anota qué rollos eran, para que el
--    buzón no pida completar un dato que no se olvidó: se borró. Solo inserta,
--    nunca impide borrar, y no hace nada mientras se borra la cuenta.

create function app_private.rolls_mark_to_develop()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'To Develop' and (tg_op = 'INSERT' or old.status is distinct from 'To Develop') then
    new.marked_to_develop_at := now();
  end if;
  return new;
end;
$$;

create trigger rolls_mark_to_develop
before insert or update of status on public.rolls
for each row execute function app_private.rolls_mark_to_develop();

create function app_private.inbox_suppress_deleted_gear()
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
    insert into public.inbox_suppressions (owner_user_id, roll_id, field)
    select r.owner_user_id, r.id, 'camera' from public.rolls r where r.camera_id = old.id
    on conflict do nothing;
  else
    insert into public.inbox_suppressions (owner_user_id, roll_id, field)
    select r.owner_user_id, r.id, 'lens' from public.rolls r where r.lens_id = old.id
    on conflict do nothing;
  end if;
  return old;
end;
$$;

create trigger inbox_suppress_deleted_camera
before delete on public.cameras
for each row execute function app_private.inbox_suppress_deleted_gear();

create trigger inbox_suppress_deleted_lens
before delete on public.lenses
for each row execute function app_private.inbox_suppress_deleted_gear();

revoke all on function app_private.rolls_mark_to_develop(),
  app_private.inbox_suppress_deleted_gear() from public, anon, authenticated;
