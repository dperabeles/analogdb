-- Camera catalog, batch 2 (20261121130000): the 215 Nikon film cameras
-- Diego approved. Run after the migration (twice in the rehearsal, to show it
-- never duplicates), inside BEGIN / ROLLBACK.
do $$
declare
  nikon bigint;
begin
  select id into nikon from public.manufacturers
   where status = 'approved' and app_private.manufacturer_key(name) = 'nikon';
  assert nikon is not null, 'Nikon is an approved manufacturer';
  assert (select count(*) from public.camera_models
           where manufacturer_id = nikon and source = 'nikon' and status = 'approved') = 215,
    'the whole batch';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1982 and interchangeable = true
                 and mount_id = (select id from public.lens_mounts where name = 'Nikon F' and status = 'approved')
            from public.camera_models where manufacturer_id = nikon and name = 'FM2'), 'FM2';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1959 and interchangeable = true
                 and mount_id = (select id from public.lens_mounts where name = 'Nikon F' and status = 'approved')
            from public.camera_models where manufacturer_id = nikon and name = 'F'), 'F';
  assert (select type = 'Rangefinder' and format = '35mm' and year_from = 1957 and interchangeable = true
                 and mount_id = (select id from public.lens_mounts where name = 'Nikon S' and status = 'approved')
            from public.camera_models where manufacturer_id = nikon and name = 'SP'), 'SP';
  assert (select type = 'Otro' and format = '35mm' and year_from = 1984 and interchangeable = true
                 and mount_id = (select id from public.lens_mounts where name = 'Nikonos' and status = 'approved')
            from public.camera_models where manufacturer_id = nikon and name = 'Nikonos V'), 'Nikonos V';
  assert (select type = 'P&S' and format = '35mm' and year_from = 1993 and interchangeable = false
                 and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models where manufacturer_id = nikon and name = '35Ti'), '35Ti';
  assert (select type = 'SLR' and format = 'APS' and year_from = 1998 and interchangeable = true
                 and mount_id = (select id from public.lens_mounts where name = 'Nikon F' and status = 'approved')
            from public.camera_models where manufacturer_id = nikon and name = 'Pronea S'), 'Pronea S';
  assert (select count(*) from public.camera_models where manufacturer_id = nikon
           and name in ('F80', 'N80', 'Nikomat FT', 'Nikkormat FT')) = 4,
    'each regional name is its own model';
  assert not exists (select 1 from public.camera_models where manufacturer_id = nikon and source = 'nikon'
                      and (name ~ ' (QD|Date)$' or name ~ '^F\d+D$' or source_ref is null or mount_id is null)),
    'no date variants, every model has its source and mount';
end $$;
