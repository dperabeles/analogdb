-- The trash keeps a copy of what someone deletes for 30 days (ANA-192).
--
-- `deleted_rows` (20260918040000_salvaguardas_borrado) copies every row a
-- person deletes so a mistake can be undone by an admin. Until now those
-- copies stayed forever unless the account was deleted
-- (20261022213650_purge_trash_on_account_delete). The privacy policy now
-- promises 30 days, so a daily job removes older copies.

create index if not exists deleted_rows_borrado_en_idx on public.deleted_rows (borrado_en);

create function app_private.purge_old_trash()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  delete from public.deleted_rows where borrado_en < now() - interval '30 days';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function app_private.purge_old_trash() from public, anon, authenticated;

comment on table public.deleted_rows is
  'Papelera. Cada fila borrada se copia aquí ANTES de irse, salvo las que se '
  'van por cierre de cuenta (esas deben desaparecer de verdad). Las copias se '
  'borran a los 30 días (trash_purge) o al cerrar la cuenta.';

select cron.unschedule(j.jobid) from cron.job j where j.jobname = 'trash_purge';
select cron.schedule('trash_purge', '17 9 * * *', 'select app_private.purge_old_trash()');
