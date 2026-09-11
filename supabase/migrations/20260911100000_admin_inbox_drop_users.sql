-- admin_inbox(): fuera 'users_pending'
--
-- El alta de cuentas ya es automática: `handle_new_auth_user` inserta
-- 'approved' y el default de la columna también lo es. Y no es que esté
-- vacío por ahora — `admin_set_profile_status` solo acepta 'approved' o
-- 'rejected', así que NADA puede producir una cuenta pendiente. El contador
-- estaba estructuralmente muerto.
--
-- Un avisador que cuenta algo que nunca pasa es peor que inútil: enseña a
-- desconfiar del resto.
--
-- ── Lo que esto demuestra ───────────────────────────────────────────────
--
-- Este cambio NO necesita una versión nueva de la app. El badge pinta el
-- `total` que manda el servidor y no interpreta las claves, así que al
-- recargar ya cuenta una cosa menos. Era justo el motivo de sumar aquí y no
-- en el cliente.
create or replace function public.admin_inbox()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_labs int;
  v_roles int;
begin
  if not public.app_is_admin(auth.uid()) then
    return jsonb_build_object('total', 0, 'items', jsonb_build_object());
  end if;

  select count(*) into v_labs  from public.labs          where status = 'pending';
  select count(*) into v_roles from public.admin_actions where status = 'pending';

  return jsonb_build_object(
    'total', v_labs + v_roles,
    'items', jsonb_build_object(
      'labs_pending',  v_labs,
      'role_requests', v_roles
    )
  );
end $$;
