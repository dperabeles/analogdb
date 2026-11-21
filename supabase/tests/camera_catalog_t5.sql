-- Camera catalog, batch 5 (20261121160000): 135 models (Soviet cameras,
-- Fujica, Agfa, large format and cine) Diego approved. Run after the
-- migration (twice in the rehearsal, to show it never duplicates), inside
-- BEGIN / ROLLBACK.
do $$
begin
  -- Exactly this batch's models, by key (as loaded). A later batch or a merge
  -- in the panel never changes this count; deleting one does.
  assert (select count(distinct (app_private.manufacturer_key(mf.name), app_private.camera_model_key(c.name)))
            from public.camera_models c
            join public.manufacturers mf on mf.id = c.manufacturer_id
           where c.status in ('approved', 'merged')
             and (app_private.manufacturer_key(mf.name), app_private.camera_model_key(c.name)) in (
               select app_private.manufacturer_key(v.maker), app_private.camera_model_key(v.name)
                 from (values
                 ('Kiev', '2'),
                 ('Kiev', '2A'),
                 ('Kiev', '3'),
                 ('Kiev', '3A'),
                 ('Kiev', '4'),
                 ('Kiev', '4A'),
                 ('Kiev', '4M'),
                 ('Kiev', '4AM'),
                 ('Kiev', '5'),
                 ('Kiev', '17'),
                 ('Kiev', '19'),
                 ('Kiev', '19M'),
                 ('Kiev', '20'),
                 ('Kiev', '10'),
                 ('Kiev', '15'),
                 ('Kiev', '6C'),
                 ('Kiev', '60'),
                 ('Kiev', '88'),
                 ('Kiev', '88CM'),
                 ('Kiev', 'Salyut'),
                 ('Kiev', 'Salyut-S'),
                 ('Kiev', '35A'),
                 ('FED', '1'),
                 ('FED', '2'),
                 ('FED', '3'),
                 ('FED', '4'),
                 ('FED', '5'),
                 ('FED', '5B'),
                 ('FED', '5C'),
                 ('FED', '35'),
                 ('FED', '50'),
                 ('FED', 'Micron'),
                 ('FED', 'Micron 2'),
                 ('LOMO', 'LC-A'),
                 ('LOMO', 'Lubitel 2'),
                 ('LOMO', 'Lubitel 166'),
                 ('LOMO', 'Lubitel 166B'),
                 ('LOMO', 'Lubitel 166 Universal'),
                 ('LOMO', 'Smena 8'),
                 ('LOMO', 'Smena 8M'),
                 ('LOMO', 'Smena Symbol'),
                 ('LOMO', 'Smena 35'),
                 ('LOMO', 'Almaz-103'),
                 ('Fujica', 'ST601'),
                 ('Fujica', 'ST605'),
                 ('Fujica', 'ST605N'),
                 ('Fujica', 'ST701'),
                 ('Fujica', 'ST705'),
                 ('Fujica', 'ST801'),
                 ('Fujica', 'ST901'),
                 ('Fujica', 'AX-1'),
                 ('Fujica', 'AX-3'),
                 ('Fujica', 'AX-5'),
                 ('Fujica', 'STX-1'),
                 ('Fujica', 'STX-2'),
                 ('Fujica', 'Half'),
                 ('Agfa', 'Optima'),
                 ('Agfa', 'Optima 1535'),
                 ('Agfa', 'Silette'),
                 ('Agfa', 'Isolette'),
                 ('Agfa', 'Isolette III'),
                 ('Agfa', 'Isola'),
                 ('Agfa', 'Clack'),
                 ('Agfa', 'Synchro Box'),
                 ('Linhof', 'Technika III'),
                 ('Linhof', 'Technika IV'),
                 ('Linhof', 'Technika V'),
                 ('Linhof', 'Master Technika'),
                 ('Graflex', 'Speed Graphic'),
                 ('Graflex', 'Crown Graphic'),
                 ('Toyo', '45A'),
                 ('Toyo', '45AII'),
                 ('Toyo', '45CF'),
                 ('Toyo', 'View 45G'),
                 ('Wista', '45'),
                 ('Chamonix', '45N-2'),
                 ('Intrepid', '4x5 Mk4'),
                 ('Sinar', 'F'),
                 ('Sinar', 'F2'),
                 ('Sinar', 'P'),
                 ('Sinar', 'Norma'),
                 ('Shen Hao', 'HZX45-IIA'),
                 ('Canon', 'Zoom 518 Super 8'),
                 ('Canon', 'Zoom 318 Super 8'),
                 ('Canon', 'Scoopic 16'),
                 ('Canon', 'Auto Zoom 814 Super 8'),
                 ('Canon', 'Auto Zoom 518 Super 8'),
                 ('Canon', 'Auto Zoom 1218 Super 8'),
                 ('Canon', 'Zoom 250 Super 8'),
                 ('Canon', 'Sound Scoopic 100'),
                 ('Canon', 'Sound Scoopic 200'),
                 ('Canon', 'Auto Zoom 518 SV'),
                 ('Canon', 'Auto Zoom 814 Electronic'),
                 ('Canon', 'Auto Zoom 318M'),
                 ('Canon', 'Sound Scoopic 200S'),
                 ('Canon', 'Sound Scoopic 200SE'),
                 ('Canon', 'Sound Scoopic 200S10'),
                 ('Canon', 'Auto Zoom 1014 Electronic'),
                 ('Canon', 'Scoopic 16M'),
                 ('Canon', 'Scoopic 16MN'),
                 ('Canon', 'Auto Zoom 512XL Electronic'),
                 ('Canon', '310XL'),
                 ('Canon', '514XL'),
                 ('Canon', '514XL-S'),
                 ('Canon', 'Scoopic 16MS'),
                 ('Canon', '814XL Electronic'),
                 ('Canon', '312XL-S'),
                 ('Canon', 'Systema Sound 16'),
                 ('Canon', '1014XL-S'),
                 ('Canon', '814XL-S'),
                 ('Canon', 'AF514XL-S'),
                 ('Canon', 'AF310XL'),
                 ('Canon', 'AF310XL-S'),
                 ('Nikon', 'R8 Super Zoom'),
                 ('Nikon', 'R10 Super Zoom'),
                 ('Nikon', 'Super Zoom 8'),
                 ('Minolta', 'XL-401'),
                 ('Minolta', 'XL-601'),
                 ('Minolta', 'Autopak-8 D10'),
                 ('Beaulieu', '4008 ZM'),
                 ('Beaulieu', '4008 ZM II'),
                 ('Beaulieu', '4008 ZM4'),
                 ('Beaulieu', '6008 S'),
                 ('Beaulieu', '7008 Pro'),
                 ('Braun', 'Nizo S56'),
                 ('Braun', 'Nizo S560'),
                 ('Braun', 'Nizo S800'),
                 ('Braun', 'Nizo 6080'),
                 ('Braun', 'Nizo Professional'),
                 ('Elmo', 'Super 110'),
                 ('Elmo', '1012S-XL'),
                 ('Bolex', 'H16 Reflex'),
                 ('Bolex', 'H16 Rex-4'),
                 ('Bolex', 'H16 Rex-5'),
                 ('Krasnogorsk', '3')
               ) v(maker, name))) = 135, 'the whole batch';
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
