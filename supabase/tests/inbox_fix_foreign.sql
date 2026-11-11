-- Review fix: another account's roll pointing at your camera changes nothing in
-- your inbox, and teaches its owner nothing about your camera.
do $$
declare
  a uuid := pg_temp.buzon_user('ff_a');
  b uuid := pg_temp.buzon_user('ff_b');
  cam1 bigint := pg_temp.buzon_camera(a);
  cam2 bigint := pg_temp.buzon_camera(a);
  cam3 bigint := pg_temp.buzon_camera(a, 'Leica M');
  rb bigint;
begin
  insert into public.inbox_accounts (user_id, activated_at) values (a, now() - interval '1 day'), (b, now() - interval '1 day');
  -- roll_gear_same_owner forbids these rolls; its guard is switched off while
  -- they are created, to keep checking the inbox's own line of defence.
  if exists (select 1 from pg_trigger where tgrelid = 'public.rolls'::regclass and tgname = 'rolls_gear_same_owner') then
    alter table public.rolls disable trigger rolls_gear_same_owner;
  end if;
  -- B's roll with a lens on A's camera is no proof for A.
  perform pg_temp.buzon_roll(b, 'Developed', cam1, pg_temp.buzon_lens(b));
  assert app_private.inbox_camera_kind(cam1) = 'unknown', 'a foreign roll with lens is no proof';
  -- B's fixed_camera frame on A's camera does not silence A.
  rb := pg_temp.buzon_roll(b, 'Developed', cam2);
  insert into public.roll_exposures (roll_id, frame_number, lens_source) values (rb, 1, 'fixed_camera');
  assert app_private.inbox_camera_kind(cam2) = 'unknown', 'a foreign fixed_camera frame is no proof';
  -- B's lensless rolls on A's cameras give B no lens notice and no question.
  rb := pg_temp.buzon_roll(b, 'Developed', cam3);
  if exists (select 1 from pg_trigger where tgrelid = 'public.rolls'::regclass and tgname = 'rolls_gear_same_owner') then
    alter table public.rolls enable trigger rolls_gear_same_owner;
  end if;
  assert not exists (select 1 from app_private.inbox_roll_gaps(b) g where g.roll_id = rb and g.kind <> 'missing_lab'),
         'no lens notice from a foreign camera';
  assert not exists (select 1 from app_private.inbox_roll_gaps(b) g where g.camera_id in (cam1, cam2, cam3)),
         'no question about a foreign camera';
end $$;
