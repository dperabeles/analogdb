-- Camera catalog, batch 4 (20261121150000): 374 models of 19 other
-- brands Diego approved. Run after the migration (twice in the rehearsal, to
-- show it never duplicates), inside BEGIN / ROLLBACK.
do $$
begin
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Leica')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 35, 'Leica';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Hasselblad')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 23, 'Hasselblad';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Fujifilm')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 36, 'Fujifilm';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Mamiya')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 31, 'Mamiya';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Bronica')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 14, 'Bronica';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Contax')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 29, 'Contax';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Yashica')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 34, 'Yashica';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Rollei')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 25, 'Rollei';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Konica')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 18, 'Konica';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Ricoh')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 14, 'Ricoh';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Voigtländer')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 16, 'Voigtländer';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Zenit')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 23, 'Zenit';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Zorki')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 14, 'Zorki';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Praktica')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 16, 'Praktica';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Pentacon')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 2, 'Pentacon';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Kodak')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 21, 'Kodak';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Polaroid')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 14, 'Polaroid';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Lomography')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 5, 'Lomography';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Holga')
             and c.status = 'approved' and c.source in ('curada', 'wikidata')) = 4, 'Holga';
  assert (select type = 'Rangefinder' and format = '35mm' and year_from = 1984 and mount_id = (select id from public.lens_mounts where name = 'Leica M' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Leica') and c.name = 'M6'), 'Leica M6';
  assert (select type = 'SLR' and format = '120' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Hasselblad V' and status = 'approved') and frame_sizes = '{6x4.5,6x6}'::text[]
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Hasselblad') and c.name = '500C/M'), 'Hasselblad 500C/M';
  assert (select type = 'SLR' and format = '120' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Mamiya RB67' and status = 'approved') and frame_sizes = '{6x4.5,6x7,6x8}'::text[]
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Mamiya') and c.name = 'RB67 Pro S'), 'Mamiya RB67 Pro S';
  assert (select type = 'Instantánea' and format = 'Instax Mini' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Fujifilm') and c.name = 'Instax Mini 11'), 'Fujifilm Instax Mini 11';
  assert (select type = 'SLR' and format = '35mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'M42' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Zenit') and c.name = 'E'), 'Zenit E';
  assert (select type = 'Rangefinder' and format = '35mm' and year_from = 1956 and mount_id = (select id from public.lens_mounts where name = 'Leica LTM (L39)' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Zorki') and c.name = '4'), 'Zorki 4';
  assert (select type = 'Instantánea' and format = 'Polaroid SX-70' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Polaroid') and c.name = 'SX-70'), 'Polaroid SX-70';
  assert (select type = 'Instantánea' and format is null and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Lente integrado' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Polaroid') and c.name = 'Go'), 'Polaroid Go';
  assert (select type = 'Rangefinder' and format = '35mm' and year_from is null and mount_id = (select id from public.lens_mounts where name = 'Leica M' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Voigtländer') and c.name = 'Bessa R2A'), 'Voigtländer Bessa R2A';
  assert (select type = 'SLR' and format = '120' and year_from is null and mount_id is null and frame_sizes = '{6x8}'::text[]
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where app_private.manufacturer_key(mf.name) = app_private.manufacturer_key('Fujifilm') and c.name = 'GX680'), 'Fujifilm GX680';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where (mf.name, c.name) in (('Hasselblad', 'XPan'), ('Fujifilm', 'TX-1'))) = 2,
    'each regional name is its own model';
end $$;
