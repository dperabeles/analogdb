-- Camera catalog, batch 6 (20261121230000). Run after the migration, inside
-- BEGIN / ROLLBACK, after film_inventory_helpers.sql.
do $$
declare
  a uuid; mk bigint; six bigint; j bigint;
begin
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where c.status = 'approved' and (mf.name, c.name) in (
             ('Pentax', 'Super Program'), ('Pentax', 'PC-330'), ('Pentax', 'IQZoom 115M'),
             ('Yashica', 'FX-2'), ('Yashica', 'EZS Zoom 105'), ('Minox', '35 GL'), ('Fujica', 'V2'))) = 7,
    'the seven models';
  assert (select type = 'SLR' and format = '35mm' and year_from = 1983
             and mount_id = (select id from public.lens_mounts where name = 'Pentax K' and status = 'approved')
            from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Pentax' and c.name = 'Super Program'), 'Pentax Super Program';
  assert (select count(*) from public.camera_models c join public.manufacturers mf on mf.id = c.manufacturer_id
           where mf.name = 'Pentax' and c.name in ('Super A', 'Super Program') and c.status = 'approved') = 2,
    'the Super A stays its own model';
  assert exists (select 1 from public.manufacturers where name = 'Minox' and status = 'approved'), 'Minox is a maker';

  -- A short key no longer suggests: «6» inside «645J».
  a := pg_temp.inv_user('t6a');
  insert into public.manufacturers (name, status) values ('Prueba Seis', 'approved') returning id into mk;
  insert into public.camera_models (manufacturer_id, name, status, source) values (mk, '6', 'approved', 'curada') returning id into six;
  insert into public.camera_models (manufacturer_id, name, status, source) values (mk, 'M645 J', 'approved', 'curada') returning id into j;
  assert app_private.camera_text_suggestion('Prueba Seis', 'Prueba Seis 645J') = j, '645J suggests M645 J';
  assert app_private.camera_text_suggestion('Prueba Seis', 'algo 6') is distinct from six, 'a one-character key suggests nothing';
end $$;
