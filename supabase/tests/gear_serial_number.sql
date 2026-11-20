-- An optional serial number for cameras and lenses (20261121200000). Run
-- inside BEGIN / ROLLBACK after film_inventory_helpers.sql. Synthetic
-- accounts only.
do $$
declare
  a uuid; b uuid; cam bigint; lens bigint;
begin
  a := pg_temp.inv_user('sera');
  b := pg_temp.inv_user('serb');

  perform pg_temp.como(a);
  insert into public.cameras (owner_user_id, maker, model, serial_number)
  values (a, 'Prueba Serie', 'Cámara', '1234567') returning id into cam;
  insert into public.lenses (owner_user_id, maker, model, serial_number)
  values (a, 'Prueba Serie', 'Lente', 'L-998') returning id into lens;
  assert (select serial_number from public.cameras where id = cam) = '1234567', 'a camera keeps its serial';
  assert (select serial_number from public.lenses where id = lens) = 'L-998', 'a lens keeps its serial';
  update public.cameras set serial_number = null where id = cam;
  assert (select serial_number is null from public.cameras where id = cam), 'it can be taken away';
  update public.cameras set serial_number = 'AB-1' where id = cam;
  perform pg_temp.espera_error(format('update public.cameras set serial_number = %L where id = %s', '   ', cam), '23514');
  perform pg_temp.espera_error(format('update public.lenses set serial_number = %L where id = %s', repeat('9', 65), lens), '23514');
  perform pg_temp.yo();

  -- Only its owner sees it.
  perform pg_temp.como(b);
  assert not exists (select 1 from public.cameras where id = cam), 'B never sees A''s camera';
  assert not exists (select 1 from public.lenses where id = lens), 'nor A''s lens';
  update public.cameras set serial_number = 'robado' where id = cam;
  perform pg_temp.yo();
  assert (select serial_number from public.cameras where id = cam) = 'AB-1', 'B cannot change it';
  perform pg_temp.como(null);
  perform pg_temp.espera_error('select serial_number from public.cameras', '42501');
  perform pg_temp.yo();
end $$;
