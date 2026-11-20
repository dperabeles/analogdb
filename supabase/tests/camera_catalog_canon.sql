-- Camera catalog, batch 1 (20261121120000): the 253 Canon film cameras
-- Diego approved. Run after the migration (twice in the rehearsal, to show it
-- never duplicates), inside BEGIN / ROLLBACK.
do $$
declare
  canon bigint;
begin
  select id into canon from public.manufacturers
   where status = 'approved' and app_private.manufacturer_key(name) = 'canon';
  assert canon is not null, 'Canon is an approved manufacturer';
  assert (select count(*) from public.camera_models
           where manufacturer_id = canon and source = 'canon' and status = 'approved') = 253,
    'the whole batch';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1981 and interchangeable
                 and mount_id = (select id from public.lens_mounts where name = 'Canon FD' and status = 'approved')
            from public.camera_models where manufacturer_id = canon and name = 'AE-1 Program'),
    'AE-1 Program';
  assert (select type = 'SLR' and format = '35mm' and year_from = 2000
                 and mount_id = (select id from public.lens_mounts where name = 'Canon EF' and status = 'approved')
            from public.camera_models where manufacturer_id = canon and name = 'EOS-1V'),
    'EOS-1V';
  assert (select type = 'Rangefinder' and format = '35mm' and year_from = 1965 and not interchangeable
                 and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models where manufacturer_id = canon and name = 'Canonet QL17'),
    'Canonet QL17';
  assert (select count(*) from public.camera_models where manufacturer_id = canon and name in ('EOS 3000', 'EOS 88')) = 2,
    'each regional name is its own model';
  assert not exists (select 1 from public.camera_models where manufacturer_id = canon and source = 'canon'
                      and (name ~ '(QD|Date|Caption)$' or name ~ '/' or source_ref is null)),
    'no date variants, no slashes, every model has its source';
  assert (select count(*) from public.camera_models where manufacturer_id = canon and source = 'canon'
            and mount_id is null) = 8, 'the 8 with no confirmed mount stay empty';
end $$;
