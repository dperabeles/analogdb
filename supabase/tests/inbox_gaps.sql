-- Inbox gaps: what each roll is missing and what is known about each camera.
create function pg_temp.gap(p_uid uuid, p_kind text, p_roll bigint, p_camera bigint default null)
returns int language sql as $$
  select count(*)::int from app_private.inbox_roll_gaps(p_uid) g
  where g.kind = p_kind and g.roll_id is not distinct from p_roll
    and g.camera_id is not distinct from p_camera;
$$;

create function pg_temp.frame(p_roll bigint, p_source text) returns void language sql as $$
  insert into public.roll_exposures (roll_id, frame_number, lens_source, lens_snapshot)
  values (p_roll, 1, p_source, case when p_source in ('roll_default', 'frame_selected')
                                    then '{"version": 1, "display_name": "Test 50"}'::jsonb end);
$$;

do $$
declare
  a uuid := pg_temp.buzon_user('gap_a');
  b uuid := pg_temp.buzon_user('gap_b');
  comp bigint := pg_temp.buzon_camera(a);
  mounted bigint := pg_temp.buzon_camera(a, 'Leica M');
  proof bigint := pg_temp.buzon_camera(a);
  falsecam bigint := pg_temp.buzon_camera(a, null, false);
  fixedframe bigint := pg_temp.buzon_camera(a);
  confirmed bigint := pg_temp.buzon_camera(a);
  framecam bigint := pg_temp.buzon_camera(a);
  unknowncam bigint := pg_temp.buzon_camera(a);
  supcam bigint := pg_temp.buzon_camera(a);
  oldcam bigint := pg_temp.buzon_camera(a);
  mixcam bigint := pg_temp.buzon_camera(a);
  lens bigint := pg_temp.buzon_lens(a);
  lab bigint;
  rq1 bigint; rq2 bigint; rq3 bigint; rm1 bigint; rp1 bigint; rp2 bigint; rf bigint; rx bigint;
  rc bigint; rfl bigint; rfl2 bigint; ru bigint; rt bigint; ric bigint; rtd bigint; rdv bigint;
  rar bigint; rscan bigint; rs0 bigint; rs1 bigint; rsl bigint; ro bigint; rold bigint; rmix_old bigint;
  rmix_new bigint; rb bigint;
begin
  insert into public.inbox_accounts (user_id, activated_at) values (a, now());
  insert into public.labs (name) values ('Lab buzon test') returning id into lab;

  -- Compact with the default true, no mount, no lenses: one question, no lens asks.
  rq1 := pg_temp.buzon_roll(a, 'Developed', comp);
  rq2 := pg_temp.buzon_roll(a, 'Archived', comp);
  rq3 := pg_temp.buzon_roll(a, 'To Develop', comp);
  assert app_private.inbox_camera_kind(comp) = 'unknown', 'default true is not proof';
  assert pg_temp.gap(a, 'camera_lens_question', null, comp) = 1, 'one question per camera';
  assert (select count(*) from app_private.inbox_roll_gaps(a) g where g.kind = 'missing_lens'
          and g.roll_id in (rq1, rq2, rq3)) = 0, 'no lens asked on an unknown camera';

  -- A mount is proof.
  rm1 := pg_temp.buzon_roll(a, 'Developed', mounted);
  assert pg_temp.gap(a, 'missing_lens', rm1) = 1, 'mounted camera asks for the lens';

  -- A roll with a lens is proof for the other rolls of that camera.
  rp1 := pg_temp.buzon_roll(a, 'Developed', proof, lens);
  rp2 := pg_temp.buzon_roll(a, 'Developed', proof);
  assert app_private.inbox_camera_kind(proof) = 'interchangeable', 'roll with lens is proof';
  assert pg_temp.gap(a, 'missing_lens', rp2) = 1 and pg_temp.gap(a, 'missing_lens', rp1) = 0, 'only the roll without lens';

  -- An explicit false and a fixed_camera frame mean fixed lens.
  rf := pg_temp.buzon_roll(a, 'Developed', falsecam);
  assert app_private.inbox_camera_kind(falsecam) = 'fixed', 'explicit false is fixed';
  assert pg_temp.gap(a, 'missing_lens', rf) = 0 and pg_temp.gap(a, 'camera_lens_question', null, falsecam) = 0, 'fixed asks nothing';
  rx := pg_temp.buzon_roll(a, 'Developed', fixedframe);
  perform pg_temp.frame(rx, 'fixed_camera');
  assert app_private.inbox_camera_kind(fixedframe) = 'fixed', 'fixed_camera frame is fixed';
  assert pg_temp.gap(a, 'camera_lens_question', null, fixedframe) = 0, 'no question for a fixed_camera frame';

  -- A confirmation wins over a fixed_camera frame.
  rc := pg_temp.buzon_roll(a, 'Developed', confirmed);
  perform pg_temp.frame(rc, 'fixed_camera');
  update public.cameras set lens_setup_confirmed_at = now(), supports_interchangeable_lenses = true where id = confirmed;
  assert app_private.inbox_camera_kind(confirmed) = 'interchangeable', 'confirmation wins';
  assert pg_temp.gap(a, 'missing_lens', rc) = 1, 'confirmed interchangeable asks for the lens';

  -- A lens recorded only on a frame counts as lens, and as proof.
  rfl := pg_temp.buzon_roll(a, 'Developed', framecam);
  perform pg_temp.frame(rfl, 'frame_selected');
  rfl2 := pg_temp.buzon_roll(a, 'Developed', framecam);
  assert app_private.inbox_roll_has_lens(rfl), 'frame lens counts';
  assert pg_temp.gap(a, 'missing_lens', rfl) = 0, 'no ask when a frame has the lens';
  assert pg_temp.gap(a, 'missing_lens', rfl2) = 1, 'frame lens is proof for the camera';

  -- An unknown frame is not lens data.
  ru := pg_temp.buzon_roll(a, 'Developed', unknowncam);
  perform pg_temp.frame(ru, 'unknown');
  assert not app_private.inbox_roll_has_lens(ru), 'unknown frame is not a lens';
  assert pg_temp.gap(a, 'camera_lens_question', null, unknowncam) = 1, 'unknown frame still asks';

  -- The old lens text counts as lens.
  insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id, lens)
  values (a, 'R901', gen_random_uuid(), 'Developed', mounted, 'Summicron 50') returning id into rt;
  assert pg_temp.gap(a, 'missing_lens', rt) = 0, 'old lens text counts';

  -- In Camera is not evaluated.
  ric := pg_temp.buzon_roll(a, 'In Camera');
  assert not exists (select 1 from app_private.inbox_roll_gaps(a) g where g.roll_id = ric), 'In Camera has no gaps';
  assert pg_temp.gap(a, 'missing_camera', ric) = 0, 'In Camera without camera is fine';

  -- Labs only on developed rolls.
  rtd := pg_temp.buzon_roll(a, 'To Develop', mounted, lens);
  rdv := pg_temp.buzon_roll(a, 'Developed', mounted, lens);
  rar := pg_temp.buzon_roll(a, 'Archived', mounted, lens);
  rscan := pg_temp.buzon_roll(a, 'Archived', mounted, lens);
  update public.rolls set scan_lab_id = lab where id = rscan;
  assert pg_temp.gap(a, 'missing_lab', rtd) = 0, 'To Develop needs no lab';
  assert pg_temp.gap(a, 'missing_lab', rdv) = 1 and pg_temp.gap(a, 'missing_lab', rar) = 1, 'developed without lab';
  assert pg_temp.gap(a, 'missing_lab', rscan) = 0, 'scan lab is enough';

  -- Deleted gear is never asked.
  rs0 := pg_temp.buzon_roll(a, 'Developed');
  rs1 := pg_temp.buzon_roll(a, 'Developed');
  update public.rolls set camera_snapshot = '{"version": 1, "display_name": "Old cam"}' where id = rs1;
  assert pg_temp.gap(a, 'missing_camera', rs0) = 1, 'missing camera';
  assert pg_temp.gap(a, 'missing_camera', rs1) = 0, 'deleted camera is not asked';
  rsl := pg_temp.buzon_roll(a, 'Developed', supcam);
  update public.rolls set lens_snapshot = '{"version": 1, "display_name": "Old lens"}' where id = rsl;
  assert pg_temp.gap(a, 'camera_lens_question', null, supcam) = 0, 'deleted lens does not ask about the camera';

  -- Old and new rolls.
  ro := pg_temp.buzon_roll(a, 'Developed', mounted, lens);
  update public.rolls set created_at = now() - interval '30 days' where id = ro;
  assert (select g.is_old from app_private.inbox_roll_gaps(a) g where g.kind = 'missing_lab' and g.roll_id = ro), 'old roll';
  assert not (select g.is_old from app_private.inbox_roll_gaps(a) g where g.kind = 'missing_lab' and g.roll_id = rdv), 'new roll';
  rold := pg_temp.buzon_roll(a, 'Developed', oldcam);
  update public.rolls set created_at = now() - interval '30 days' where id = rold;
  rmix_old := pg_temp.buzon_roll(a, 'Developed', mixcam);
  update public.rolls set created_at = now() - interval '30 days' where id = rmix_old;
  rmix_new := pg_temp.buzon_roll(a, 'Developed', mixcam);
  assert (select g.is_old from app_private.inbox_roll_gaps(a) g where g.kind = 'camera_lens_question' and g.camera_id = oldcam),
         'question with only old rolls is old';
  assert not (select g.is_old from app_private.inbox_roll_gaps(a) g where g.kind = 'camera_lens_question' and g.camera_id = mixcam),
         'a new roll makes the question new';

  -- Never another account's rolls.
  rb := pg_temp.buzon_roll(b, 'Developed');
  assert not exists (select 1 from app_private.inbox_roll_gaps(a) g where g.roll_id = rb), 'no rolls of B';
end $$;
