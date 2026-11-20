-- Camera catalog, batch 3 (20261121140000): Pentax, Olympus and Minolta,
-- 198 models Diego approved. Run after the migration (twice in the
-- rehearsal, to show it never duplicates), inside BEGIN / ROLLBACK.
do $$
begin
  assert app_private.camera_model_key('α-7000') <> app_private.camera_model_key('7000'), 'α is read as alpha';
  assert app_private.camera_model_key('AE-1 Program') = app_private.camera_model_key('ae1 program'), 'the rest as before';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Pentax' and c.status = 'approved' and c.source in ('pentax', 'wikidata')) = 70, 'Pentax';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Olympus' and c.status = 'approved' and c.source in ('olympus', 'curada')) = 65, 'Olympus';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Minolta' and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 63, 'Minolta';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Minolta' and c.name in ('α-7000', 'Maxxum 7000', '7000')) = 3, 'each regional name is its own model';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1976 and mount_id = (select id from public.lens_mounts where name = 'Pentax K' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Pentax' and c.name = 'K1000'), 'Pentax K1000';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1964 and mount_id = (select id from public.lens_mounts where name = 'M42' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Pentax' and c.name = 'SP'), 'Pentax SP';
  assert (select type = 'SLR' and format = '120' and year_from = 1989 and mount_id = (select id from public.lens_mounts where name = 'Pentax 67' and status = 'approved') and frame_sizes = '{6x7}'::text[]
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Pentax' and c.name = '67'), 'Pentax 67';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1952 and mount_id is null
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Pentax' and c.name = 'Asahiflex I'), 'Pentax Asahiflex I';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1972 and mount_id = (select id from public.lens_mounts where name = 'Olympus OM' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Olympus' and c.name = 'OM-1'), 'Olympus OM-1';
  assert (select type = 'Half-frame' and format = '35mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Olympus Pen F' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Olympus' and c.name = 'Pen F'), 'Olympus Pen F';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1981 and mount_id = (select id from public.lens_mounts where name = 'Minolta SR' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Minolta' and c.name = 'X-700'), 'Minolta X-700';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1985 and mount_id = (select id from public.lens_mounts where name = 'Minolta A' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Minolta' and c.name = 'Maxxum 7000'), 'Minolta Maxxum 7000';
  assert (select type = 'Rangefinder' and format = '35mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Leica M' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Minolta' and c.name = 'CLE'), 'Minolta CLE';
end $$;
