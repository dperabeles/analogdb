-- Cerrar una cuenta también vacía su papelera.
--
-- La papelera (`deleted_rows`, 20260918040000_salvaguardas_borrado) ya no
-- archivaba lo que el cierre de cuenta borra en cascada: "una papelera
-- retendría los datos de alguien que pidió borrar su cuenta". Pero las copias
-- que la persona dejó antes, al borrar un rollo o una cámara por la vía normal,
-- se quedaban para siempre. El aviso de privacidad (§5) promete purgar la
-- cuenta.
--
-- Va como disparador en auth.users, no dentro de delete_my_account, para que
-- cubra también una cuenta borrada desde el panel de Supabase. Corre después
-- de las cascadas (los disparadores de llave foránea se ejecutan antes por
-- nombre), así que también se lleva lo que esas cascadas hayan archivado.

create function app_private.purge_account_trash()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.deleted_rows where dueno = old.id;
  return old;
end;
$$;
revoke all on function app_private.purge_account_trash() from public, anon, authenticated;

create trigger zz_purge_account_trash after delete on auth.users
for each row execute function app_private.purge_account_trash();
