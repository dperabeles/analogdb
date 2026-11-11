-- Inbox triggers: the to-develop date and deleted gear.
do $$
declare
  a uuid := pg_temp.buzon_user('trg_a');
  c uuid := pg_temp.buzon_user('trg_c');
  d uuid := pg_temp.buzon_user('trg_d');
  t0 timestamptz := now();
  r1 bigint := pg_temp.buzon_roll(a, 'In Camera');
  r2 bigint;
  cam_a bigint := pg_temp.buzon_camera(a);
  cam_b bigint := pg_temp.buzon_camera(a);
  lens_a bigint := pg_temp.buzon_lens(a);
  r_c1 bigint; r_c2 bigint; r_other bigint; r_lens bigint;
  x bigint; who uuid; n int;
begin
  -- The date is set however the roll enters To Develop.
  update public.rolls set status = 'To Develop' where id = r1;
  assert (select marked_to_develop_at from public.rolls where id = r1) >= t0, 'stamped on direct update';
  update public.rolls set marked_to_develop_at = '2026-01-01' where id = r1;
  update public.rolls set notes = 'x' where id = r1;
  assert (select marked_to_develop_at from public.rolls where id = r1) = '2026-01-01', 'other edits keep it';
  update public.rolls set status = 'To Develop' where id = r1;
  assert (select marked_to_develop_at from public.rolls where id = r1) = '2026-01-01', 'staying in To Develop keeps it';
  update public.rolls set status = 'In Camera' where id = r1;
  update public.rolls set status = 'To Develop', marked_to_develop_at = '2020-01-01' where id = r1;
  assert (select marked_to_develop_at from public.rolls where id = r1) >= t0, 're-entry restamps with server time';
  r2 := pg_temp.buzon_roll(a, 'To Develop');
  assert (select marked_to_develop_at from public.rolls where id = r2) >= t0, 'insert stamps';

  -- Deleted gear: the rolls that pointed to it keep its name (gear_delete_freeze),
  -- as the app deletes.
  r_c1 := pg_temp.buzon_roll(a, 'Developed', cam_a);
  r_c2 := pg_temp.buzon_roll(a, 'Archived', cam_a);
  r_other := pg_temp.buzon_roll(a, 'Developed', cam_b);
  r_lens := pg_temp.buzon_roll(a, 'Developed', cam_b, lens_a);
  perform pg_temp.como(a);
  delete from public.cameras where id = cam_a;
  delete from public.lenses where id = lens_a;
  perform pg_temp.yo();
  assert (select count(*) from public.rolls where camera_snapshot is not null and id in (r_c1, r_c2)) = 2,
         'both rolls of the deleted camera keep its name';
  assert (select camera_snapshot is null from public.rolls where id = r_other), 'other rolls untouched';
  assert (select lens_snapshot is not null from public.rolls where id = r_lens), 'roll of the deleted lens keeps its name';
  assert (select camera_snapshot is null from public.rolls where id = r_lens), 'its camera still exists';
  assert (select camera_id from public.rolls where id = r_c1) is null, 'the foreign key still clears the roll';

  -- Accounts being deleted, from the app and from the dashboard (Review Focus 1).
  foreach who in array array[c, d] loop
    x := pg_temp.buzon_camera(who);
    perform pg_temp.buzon_roll(who, 'Developed', x, pg_temp.buzon_lens(who));
    perform pg_temp.buzon_roll(who, 'Archived', x);
    perform pg_temp.buzon_roll(who, 'To Develop', x);
  end loop;
  perform pg_temp.como(c);
  perform public.delete_my_account();
  perform pg_temp.yo();
  perform set_config('app.borrando_cuenta', '', true);
  delete from auth.users where id = d;
  assert not exists (select 1 from auth.users where id in (c, d)), 'both accounts deleted';
  assert not exists (select 1 from public.rolls where owner_user_id in (c, d)), 'nothing left';

  -- Normal path: create, edit and delete a roll and a camera as today.
  perform pg_temp.como(a);
  insert into public.cameras (owner_user_id, maker, model) values (a, 'Test', 'Normal') returning id into x;
  update public.cameras set model = 'Normal 2' where id = x;
  insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id)
  values (a, 'R777', gen_random_uuid(), 'In Camera', x) returning id into r2;
  update public.rolls set notes = 'ok' where id = r2;
  delete from public.rolls where id = r2;
  delete from public.cameras where id = x;
  get diagnostics n = row_count;
  assert n = 1, 'camera deleted as today';
  perform pg_temp.yo();
end $$;
