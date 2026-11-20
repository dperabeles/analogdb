-- Camera catalog, batch 5 (20261121160000): 135 models (Soviet cameras,
-- Fujica, Agfa, large format and cine) Diego approved. Run after the
-- migration (twice in the rehearsal, to show it never duplicates), inside
-- BEGIN / ROLLBACK.
do $$
begin
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Kiev') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 22, 'Kiev';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('FED') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 11, 'FED';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('LOMO') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 10, 'LOMO';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Fujica') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 13, 'Fujica';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Agfa') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 8, 'Agfa';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Linhof') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 4, 'Linhof';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Graflex') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 2, 'Graflex';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Toyo') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 4, 'Toyo';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Wista') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 1, 'Wista';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Chamonix') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 1, 'Chamonix';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Intrepid') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 1, 'Intrepid';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Sinar') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 4, 'Sinar';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Shen Hao') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 1, 'Shen Hao';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Canon') and c.status = 'approved'
             and c.type = 'Cine') = 31, 'Canon';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Nikon') and c.status = 'approved'
             and c.type = 'Cine') = 3, 'Nikon';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Minolta') and c.status = 'approved'
             and c.type = 'Cine') = 3, 'Minolta';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Beaulieu') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 5, 'Beaulieu';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Braun') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 5, 'Braun';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Elmo') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 2, 'Elmo';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Bolex') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 3, 'Bolex';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Krasnogorsk') and c.status = 'approved'
             and c.source in ('curada', 'wikidata', 'canon')) = 1, 'Krasnogorsk';
  assert (select type = 'SLR' and format = '120' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Kiev 88 (Salyut)' and status = 'approved') and frame_sizes = '{6x4.5,6x6}'::text[]
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Kiev') and c.name = '88'), 'Kiev 88';
  assert (select type = 'SLR' and format = '35mm' and year_from is null and mount_id is null
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Kiev') and c.name = '10'), 'Kiev 10';
  assert (select type = 'Rangefinder' and format = '35mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Leica LTM (L39)' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('FED') and c.name = '2'), 'FED 2';
  assert (select type = 'P&S' and format = '35mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('LOMO') and c.name = 'LC-A'), 'LOMO LC-A';
  assert (select type = 'SLR' and format = '35mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'M42' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Fujica') and c.name = 'ST801'), 'Fujica ST801';
  assert (select type = 'Vista / Gran formato' and format = 'Large Format' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Tablero de lente' and status = 'approved') and frame_sizes = '{4x5}'::text[]
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Linhof') and c.name = 'Technika V'), 'Linhof Technika V';
  assert (select type = 'Cine' and format = 'Super8' and year_from = 1976 and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Canon') and c.name = '514XL-S'), 'Canon 514XL-S';
  assert (select type = 'Cine' and format = '16mm' and year_from = 1965 and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Canon') and c.name = 'Scoopic 16'), 'Canon Scoopic 16';
  assert (select type = 'Cine' and format = '16mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'C-mount' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Bolex') and c.name = 'H16 Rex-5'), 'Bolex H16 Rex-5';
  assert (select type = 'Cine' and format = '16mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'M42' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Krasnogorsk') and c.name = '3'), 'Krasnogorsk 3';
end $$;
