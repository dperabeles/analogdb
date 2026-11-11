-- Inbox evaluation: data notices with their margin, the old-rolls group and
-- resolution. Time travels with p_now; activation and creation dates are set
-- by hand. T0 = 2026-11-01 09:00 in Mexico City.
create function pg_temp.ev(p_uid uuid, p_days numeric) returns void language sql as $$
  select app_private.inbox_evaluate(p_uid, '2026-11-01 15:00Z'::timestamptz + make_interval(secs => p_days * 86400));
$$;

create function pg_temp.notice(p_uid uuid, p_kind text, p_roll bigint default null, p_camera bigint default null)
returns public.inbox_notices language sql as $$
  select * from public.inbox_notices n
  where n.owner_user_id = p_uid and n.kind = p_kind
    and n.roll_id is not distinct from p_roll and n.camera_id is not distinct from p_camera;
$$;

do $$
declare
  t0 timestamptz := '2026-11-01 15:00Z';
  a uuid := pg_temp.buzon_user('ev_a');
  mounted bigint := pg_temp.buzon_camera(a, 'Leica M');
  oc bigint := pg_temp.buzon_camera(a);
  qc bigint := pg_temp.buzon_camera(a);
  lz bigint := pg_temp.buzon_lens(a);
  lab bigint;
  ro1 bigint; ro2 bigint; ro3 bigint; ro4 bigint; roq bigint;
  rn bigint; rn2 bigint; rq bigint; rr bigint; rr2 bigint;
  n public.inbox_notices; before int; after int;
begin
  insert into public.labs (name) values ('Lab buzon test') returning id into lab;
  insert into public.inbox_accounts (user_id, activated_at) values (a, t0);

  -- Old rolls (created before activation), incomplete at activation.
  ro1 := pg_temp.buzon_roll(a, 'Developed', mounted, lz);           -- no lab
  ro2 := pg_temp.buzon_roll(a, 'Developed', null, null);              -- no camera
  ro3 := pg_temp.buzon_roll(a, 'Archived', oc);                       -- unknown camera
  ro4 := pg_temp.buzon_roll(a, 'Archived', mounted, lz);            -- complete for now
  update public.rolls set dev_lab_id = lab where id in (ro2, ro3, ro4);
  roq := pg_temp.buzon_roll(a, 'Developed', qc);                      -- unknown camera, old
  update public.rolls set dev_lab_id = lab where id = roq;
  update public.rolls set created_at = t0 - interval '30 days' where id in (ro1, ro2, ro3, ro4, roq);

  -- Activation: one group, unread, and nothing loose.
  perform pg_temp.ev(a, 0);
  n := pg_temp.notice(a, 'backlog_incomplete');
  assert n.id is not null and n.shown_at is not null and n.read_at is null, 'one unread group at activation';
  assert (select count(*) from public.inbox_notices where owner_user_id = a and kind <> 'backlog_incomplete') = 0,
         'no loose notices for old rolls';

  -- A new roll without lab: hidden for 3 local days, then unread.
  rn := pg_temp.buzon_roll(a, 'Developed', mounted, lz);
  update public.rolls set created_at = t0 + interval '1 hour' where id = rn;
  perform pg_temp.ev(a, 0.1);
  assert (pg_temp.notice(a, 'missing_lab', rn)).shown_at is null, 'day 0 hidden';
  perform pg_temp.ev(a, 1);
  perform pg_temp.ev(a, 2);
  assert (pg_temp.notice(a, 'missing_lab', rn)).shown_at is null, 'day 2 hidden';
  perform pg_temp.ev(a, 3);
  n := pg_temp.notice(a, 'missing_lab', rn);
  assert n.shown_at is not null and n.read_at is null, 'day 3 shown and unread';

  -- Completed inside the margin: it disappears without being seen.
  rn2 := pg_temp.buzon_roll(a, 'Developed', mounted, lz);
  update public.rolls set created_at = t0 + interval '1 hour' where id = rn2;
  perform pg_temp.ev(a, 3.1);
  assert (pg_temp.notice(a, 'missing_lab', rn2)).id is not null, 'detected';
  update public.rolls set dev_lab_id = lab where id = rn2;
  perform pg_temp.ev(a, 4);
  assert (pg_temp.notice(a, 'missing_lab', rn2)).id is null, 'completed inside the margin: gone';

  -- Completed after being shown: resolved. Removed again: back, unread, same row.
  update public.inbox_notices set read_at = t0 + interval '3 days' where (pg_temp.notice(a, 'missing_lab', rn)).id = id;
  update public.rolls set dev_lab_id = lab where id = rn;
  perform pg_temp.ev(a, 5);
  assert (pg_temp.notice(a, 'missing_lab', rn)).resolved_at is not null, 'resolved';
  update public.rolls set dev_lab_id = null where id = rn;
  perform pg_temp.ev(a, 6);
  n := pg_temp.notice(a, 'missing_lab', rn);
  assert n.resolved_at is null and n.read_at is null, 'back and unread';
  assert (select count(*) from public.inbox_notices where roll_id = rn) = 1, 'same row';

  -- Evaluating twice at the same moment changes nothing.
  select count(*) into before from public.inbox_notices where owner_user_id = a;
  perform pg_temp.ev(a, 6);
  select count(*) into after from public.inbox_notices where owner_user_id = a;
  assert before = after, 'identity holds';

  -- The group resolves when the old list empties, and reappears read.
  update public.rolls set dev_lab_id = lab where id = ro1;
  update public.rolls set camera_id = mounted, lens_id = lz where id = ro2;
  update public.cameras set lens_setup_confirmed_at = t0, supports_interchangeable_lenses = false where id in (oc, qc);
  perform pg_temp.ev(a, 7);
  n := pg_temp.notice(a, 'backlog_incomplete');
  assert n.resolved_at is not null, 'group resolved';
  update public.inbox_notices set read_at = t0 + interval '7 days' where id = n.id;
  update public.rolls set dev_lab_id = null where id = ro4;          -- an old roll loses its lab
  perform pg_temp.ev(a, 8);
  n := pg_temp.notice(a, 'backlog_incomplete');
  assert n.resolved_at is null and n.read_at is not null, 'group reappears without ringing';
  assert (pg_temp.notice(a, 'missing_lab', ro4)).id is null, 'old roll never gets a loose notice';

  -- "Don't show again" stays dismissed.
  update public.inbox_notices set dismissed_at = t0 + interval '8 days' where id = n.id;
  update public.rolls set dev_lab_id = null where id = ro2;
  perform pg_temp.ev(a, 9);
  n := pg_temp.notice(a, 'backlog_incomplete');
  assert n.dismissed_at is not null and n.resolved_at is null, 'dismissed group untouched';

  -- A camera question leaves the group when a new roll needs it.
  update public.cameras set lens_setup_confirmed_at = null, supports_interchangeable_lenses = true where id = qc;
  perform pg_temp.ev(a, 10);
  assert (pg_temp.notice(a, 'camera_lens_question', null, qc)).id is null, 'only old rolls: no loose question';
  rq := pg_temp.buzon_roll(a, 'Developed', qc);
  update public.rolls set created_at = t0 + interval '10 days', dev_lab_id = lab where id = rq;
  perform pg_temp.ev(a, 10.1);
  perform pg_temp.ev(a, 13);
  n := pg_temp.notice(a, 'camera_lens_question', null, qc);
  assert n.shown_at is not null and n.read_at is null, 'loose question after the margin';

  -- Review Focus 3: a roll that goes back and forth gets one notice.
  rr := pg_temp.buzon_roll(a, 'In Camera', mounted, lz);
  update public.rolls set created_at = t0 + interval '14 days' where id = rr;
  perform pg_temp.ev(a, 14);
  update public.rolls set status = 'To Develop' where id = rr;
  perform pg_temp.ev(a, 15);
  update public.rolls set status = 'In Camera' where id = rr;
  perform pg_temp.ev(a, 16);
  update public.rolls set status = 'To Develop' where id = rr;
  update public.rolls set status = 'Developed' where id = rr;
  perform pg_temp.ev(a, 17);
  update public.rolls set status = 'Archived' where id = rr;
  perform pg_temp.ev(a, 18);
  perform pg_temp.ev(a, 20);
  assert (select count(*) from public.inbox_notices where roll_id = rr) = 1, 'one notice for the whole trip';
  assert (pg_temp.notice(a, 'missing_lab', rr)).shown_at is not null, 'shown 3 days after Developed';
  update public.rolls set dev_lab_id = lab where id = rr;
  perform pg_temp.ev(a, 21);
  update public.rolls set dev_lab_id = null where id = rr;
  perform pg_temp.ev(a, 21.1);
  n := pg_temp.notice(a, 'missing_lab', rr);
  assert n.resolved_at is null and n.read_at is null, 'lab removed after being shown: back at once';

  -- Lab set and removed inside the margin: 3 days again from the last detection.
  rr2 := pg_temp.buzon_roll(a, 'Developed', mounted, lz);
  update public.rolls set created_at = t0 + interval '22 days' where id = rr2;
  perform pg_temp.ev(a, 22);
  update public.rolls set dev_lab_id = lab where id = rr2;
  perform pg_temp.ev(a, 23);
  update public.rolls set dev_lab_id = null where id = rr2;
  perform pg_temp.ev(a, 24);
  perform pg_temp.ev(a, 26);
  assert (pg_temp.notice(a, 'missing_lab', rr2)).shown_at is null, 'margin restarted: hidden on day 26';
  perform pg_temp.ev(a, 27);
  assert (pg_temp.notice(a, 'missing_lab', rr2)).shown_at is not null, 'shown on day 27';
end $$;
