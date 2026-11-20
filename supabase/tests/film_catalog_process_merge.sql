-- Film catalog, Fase 2d: the merge helper of 20261120090000 logs a merge
-- the panel can undo. pg_temp.catalog_merge only lives in the session that
-- ran the migration, so this runs only in the rehearsal (MIG=...), after
-- film_inventory_helpers.sql, inside BEGIN / ROLLBACK. Synthetic accounts only.
do $$
declare
  a uuid; adm uuid; dup bigint; keep bigint; roll1 bigint; change bigint;
begin
  a := pg_temp.inv_user('procma');
  adm := pg_temp.inv_user('procmadm');
  update public.user_roles set role = 'admin' where user_id = adm;
  -- ── A merge done by a migration is undone from the panel ──
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Proc Marca', 'Proc Keep', 400, 'COLOR', true, 'approved') returning id into keep;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Proc Marca', 'Proc Dup', 400, 'COLOR', true, 'approved') returning id into dup;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id)
  values (a, 'R990', gen_random_uuid(), dup) returning id into roll1;

  perform pg_temp.catalog_merge('Proc Marca', 'Proc Dup', 'Proc Marca', 'Proc Keep');
  assert (select film_stock_id from public.rolls where id = roll1) = keep, 'the roll moved to the kept film';
  select id into change from public.catalog_changes
   where entity = 'film_stock' and entity_id = dup and action = 'merge';
  assert change is not null and (select changed_by from public.catalog_changes where id = change) is null,
    'the merge is in the log, by no one';
  perform pg_temp.catalog_merge('Proc Marca', 'Nadie', 'Proc Marca', 'Proc Keep');  -- absent: nothing

  perform pg_temp.como(a);
  assert (select count(*) from public.catalog_changes) = 0, 'a user reads no catalog log';
  perform pg_temp.yo();
  perform pg_temp.como(adm);
  perform public.admin_film_stock_undo_merge(change);
  perform pg_temp.yo();
  assert (select film_stock_id from public.rolls where id = roll1) = dup, 'undo gives the roll back';
  assert (select status from public.film_stocks where id = dup) = 'approved', 'and the film';
end $$;
