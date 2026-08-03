-- Borrado de cuenta por el propio usuario.
--
-- Requisito de App Store 5.1.1(v): toda app que permite CREAR una cuenta
-- debe permitir BORRARLA desde dentro de la app. No basta un correo ni un
-- formulario web — es causa de rechazo en revisión.
--
-- El cliente no tiene (ni debe tener) permisos sobre `auth.users`, así que
-- el borrado vive en una función security definer. Es deliberadamente
-- SIN PARÁMETROS: el id sale de auth.uid(), de modo que un usuario solo
-- puede borrarse a sí mismo aunque llame al RPC a mano.
--
-- El resto cae por las FK en cascada, ya verificadas en producción:
--   auth.users → profiles → push_log
--   auth.users → rolls → roll_exposures
--   auth.users → cameras, lenses, user_roles
-- Las referencias de "quién aprobó/otorgó" (profiles.approved_by,
-- user_roles.granted_by) son SET NULL: borrar a un admin no debe borrar
-- los perfiles que aprobó.

begin;

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- Candado del founder: es la única cuenta irreemplazable del proyecto
  -- (is_founder es exclusivo del dueño) y perderla no tiene vuelta atrás.
  -- App Review nunca lo toca: los revisores usan su propia cuenta de prueba.
  if exists (
    select 1 from public.user_roles
    where user_id = uid and is_founder
  ) then
    raise exception 'founder account cannot be self-deleted';
  end if;

  delete from auth.users where id = uid;
end;
$$;

-- Solo usuarios autenticados; nunca anon ni public.
revoke all on function public.delete_my_account() from public;
revoke all on function public.delete_my_account() from anon;
grant execute on function public.delete_my_account() to authenticated;

commit;
