-- admin_inbox(): qué tiene pendiente el admin, en una sola llamada
--
-- Diego lo pidió general, no solo para labs: "en general para las cosas que
-- hagamos en un futuro que puedan generar cosas de mi parte, me gustaría
-- saber que tengo acciones que hacer".
--
-- De ahí la forma: devuelve un `total` YA SUMADO en el servidor más el
-- desglose. La app pinta el badge con `total` y no interpreta las claves, así
-- que **añadir un tipo de acción nuevo aquí hace que el badge lo cuente sin
-- reinstalar la app**. Si en cambio la app sumara las claves que conoce, cada
-- tipo nuevo exigiría una versión nueva y el badge mentiría mientras tanto.
--
-- Barata a propósito: son tres COUNT sobre columnas indexadas y se llama al
-- abrir la app. Nada de traer filas.
create or replace function public.admin_inbox()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_users int;
  v_labs int;
  v_roles int;
begin
  -- No es admin: cero, sin filtrar nada ni revelar por qué. La app trata el
  -- cero igual que "nada que hacer" y no pinta badge.
  if not public.app_is_admin(auth.uid()) then
    return jsonb_build_object('total', 0, 'items', jsonb_build_object());
  end if;

  select count(*) into v_users from public.profiles where status = 'pending';
  select count(*) into v_labs  from public.labs     where status = 'pending';
  select count(*) into v_roles from public.admin_actions where status = 'pending';

  return jsonb_build_object(
    'total', v_users + v_labs + v_roles,
    'items', jsonb_build_object(
      'users_pending', v_users,
      'labs_pending',  v_labs,
      'role_requests', v_roles
    )
  );
end $$;

revoke all on function public.admin_inbox() from public, anon;
grant execute on function public.admin_inbox() to authenticated;
