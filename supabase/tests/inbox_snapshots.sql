-- Deleted gear through the names saved on the roll (gear_delete_freeze), which
-- replace inbox_suppressions (Diego, 22-oct).
do $$
declare
  a uuid := pg_temp.buzon_user('sn_a');
  cam bigint := pg_temp.buzon_camera(a, 'Leica M');
  cam2 bigint := pg_temp.buzon_camera(a);
  lens bigint := pg_temp.buzon_lens(a);
  r1 bigint; r2 bigint; r3 bigint; r4 bigint;
begin
  assert to_regclass('public.inbox_suppressions') is null, 'the suppressions table is gone';
  insert into public.inbox_accounts (user_id, activated_at) values (a, now() - interval '1 day');
  r1 := pg_temp.buzon_roll(a, 'Developed', cam);
  r2 := pg_temp.buzon_roll(a, 'Developed', cam, lens);
  r3 := pg_temp.buzon_roll(a, 'Developed', cam2);
  -- Deleting a camera saves its name on the roll: no missing_camera.
  perform pg_temp.como(a);
  delete from public.cameras where id = cam;
  delete from public.lenses where id = lens;
  perform pg_temp.yo();
  assert (select camera_id is null and camera_snapshot is not null from public.rolls where id = r1), 'name saved';
  assert not exists (select 1 from app_private.inbox_roll_gaps(a) g
                     where g.kind = 'missing_camera' and g.roll_id in (r1, r2)), 'a deleted camera is not asked';
  -- A deleted lens still counts as lens.
  assert app_private.inbox_roll_has_lens(r2), 'a saved lens name counts';
  -- A saved lens name proves the camera takes lenses.
  update public.rolls set lens_snapshot = '{"version": 1, "display_name": "Old 50"}' where id = r3;
  r4 := pg_temp.buzon_roll(a, 'Developed', cam2);
  assert app_private.inbox_camera_kind(cam2) = 'interchangeable', 'a saved lens name is proof';
  assert exists (select 1 from app_private.inbox_roll_gaps(a) g where g.kind = 'missing_lens' and g.roll_id = r4),
         'so its other rolls ask for the lens';
end $$;
