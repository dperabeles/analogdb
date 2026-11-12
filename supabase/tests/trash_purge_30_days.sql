-- ANA-192. Run after 20261112190000_trash_purge_30_days, in a transaction
-- that ends in RAISE (nothing stays). The trash keeps a deleted row for 30
-- days; the daily job removes older copies and nothing else.
-- Expected: ENSAYO PAPELERA OK.
set local lock_timeout = '5s';
set local statement_timeout = '120s';
do $$
declare res text := ''; n int; viejas_reales int; recientes_reales int; job text;
begin
  select count(*) filter (where borrado_en < now() - interval '30 days'),
         count(*) filter (where borrado_en >= now() - interval '30 days')
    into viejas_reales, recientes_reales from public.deleted_rows;

  insert into public.deleted_rows (tabla, fila_id, dueno, fila, borrado_en) values
    ('zz_ensayo', 'vieja',   null, '{}'::jsonb, now() - interval '31 days'),
    ('zz_ensayo', 'limite',  null, '{}'::jsonb, now() - interval '29 days 23 hours'),
    ('zz_ensayo', 'reciente', null, '{}'::jsonb, now() - interval '1 day');

  n := app_private.purge_old_trash();
  if n <> 1 + viejas_reales then
    res := res || 'FALLA purgó ' || n || ' filas, se esperaban ' || (1 + viejas_reales) || '; ';
  end if;
  if exists (select 1 from public.deleted_rows where tabla = 'zz_ensayo' and fila_id = 'vieja') then
    res := res || 'FALLA quedó la copia de 31 días; ';
  end if;
  select count(*) into n from public.deleted_rows where tabla = 'zz_ensayo' and fila_id in ('limite', 'reciente');
  if n <> 2 then res := res || 'FALLA borró copias de menos de 30 días; '; end if;
  select count(*) into n from public.deleted_rows where tabla <> 'zz_ensayo';
  if n <> recientes_reales then
    res := res || 'FALLA quedaron ' || n || ' copias reales, se esperaban las ' || recientes_reales || ' de menos de 30 días; ';
  end if;

  select command into job from cron.job where jobname = 'trash_purge';
  if job is distinct from 'select app_private.purge_old_trash()' then
    res := res || 'FALLA no hay trabajo diario trash_purge; ';
  end if;

  if has_function_privilege('authenticated', 'app_private.purge_old_trash()', 'execute')
     or has_function_privilege('anon', 'app_private.purge_old_trash()', 'execute') then
    res := res || 'FALLA una cuenta puede llamar la purga; ';
  end if;

  assert res = '', res;
  raise exception 'ENSAYO PAPELERA OK: borra solo lo de más de 30 días, conserva las copias reales recientes, corre a diario, nadie más la llama';
end $$;
