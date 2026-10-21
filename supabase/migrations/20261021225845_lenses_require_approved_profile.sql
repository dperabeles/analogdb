-- ANA-150: las políticas de lentes no comprobaban que el perfil estuviera aprobado.
--
-- Cámaras, rolls y exposiciones exigen perfil aprobado; lentes se creó en
-- 20260505_add_camera_lens_mounts solo con el filtro de dueño. Esto las iguala
-- con las demás y con supabase/schema.sql, que ya las declara así.
--
-- Ensayada el 2026-10-21 en staging y en producción, con rollback, con cuentas
-- sintéticas (aprobada, otra aprobada, pendiente, rechazada y sin sesión): las
-- aprobadas no cambian, la pendiente y la rechazada pierden acceso a sus
-- lentes, nadie ve ni toca lentes ajenos. En producción todos los lentes eran
-- de cuentas aprobadas, así que nadie perdió nada.

drop policy if exists lenses_owner_select on public.lenses;
create policy lenses_owner_select
on public.lenses
for select
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

drop policy if exists lenses_owner_insert on public.lenses;
create policy lenses_owner_insert
on public.lenses
for insert
to public
with check (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);

drop policy if exists lenses_owner_update on public.lenses;
create policy lenses_owner_update
on public.lenses
for update
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
)
with check (owner_user_id = auth.uid());

drop policy if exists lenses_owner_delete on public.lenses;
create policy lenses_owner_delete
on public.lenses
for delete
to public
using (
  owner_user_id = auth.uid()
  and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.status = 'approved'
  )
);
