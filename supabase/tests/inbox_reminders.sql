-- Inbox reminders: to-develop days 14 and 44, cleanup and the hourly tick.
-- T0 = 2026-11-01 15:00Z (09:00 in Mexico City).
create function pg_temp.ev(p_uid uuid, p_days numeric) returns void language sql as $$
  select app_private.inbox_evaluate(p_uid, '2026-11-01 15:00Z'::timestamptz + make_interval(secs => p_days * 86400));
$$;

create function pg_temp.dr(p_uid uuid) returns public.inbox_notices language sql as $$
  select * from public.inbox_notices n where n.owner_user_id = p_uid and n.kind = 'develop_reminder';
$$;

create function pg_temp.waiting(p_uid uuid, p_marked timestamptz) returns bigint language plpgsql as $$
declare v bigint := pg_temp.buzon_roll(p_uid, 'To Develop');
begin
  update public.rolls set marked_to_develop_at = p_marked where id = v;
  return v;
end $$;

do $$
declare
  t0 timestamptz := '2026-11-01 15:00Z';
  a uuid := pg_temp.buzon_user('rem_a');
  b uuid := pg_temp.buzon_user('rem_b');
  c uuid := pg_temp.buzon_user('rem_c');
  d uuid := pg_temp.buzon_user('rem_d');
  e uuid := pg_temp.buzon_user('rem_e');
  g uuid := pg_temp.buzon_user('rem_g');
  kiri uuid := pg_temp.buzon_user('rem_kiri', 'approved', 'Pacific/Kiritimati');
  la uuid := pg_temp.buzon_user('rem_la', 'approved', 'America/Los_Angeles');
  ra bigint; rd bigint; re bigint; rk bigint; pol uuid; x uuid;
  n public.inbox_notices;
begin
  insert into public.inbox_accounts (user_id, activated_at)
  select u, t0 from unnest(array[a, b, c, d, e, g, kiri, la]) u;

  -- Day 14 and day 44, then silence; one row the whole time.
  ra := pg_temp.waiting(a, t0);
  perform pg_temp.ev(a, 13);
  assert (pg_temp.dr(a)).id is null, 'day 13: nothing';
  perform pg_temp.ev(a, 14);
  n := pg_temp.dr(a);
  assert n.shown_at is not null and n.read_at is null, 'day 14: unread';
  update public.inbox_notices set read_at = t0 + interval '14 days' where id = n.id;
  perform pg_temp.ev(a, 30);
  assert (pg_temp.dr(a)).read_at is not null, 'day 30: still read';
  perform pg_temp.ev(a, 44);
  assert (pg_temp.dr(a)).read_at is null, 'day 44: unread again';
  update public.inbox_notices set read_at = t0 + interval '44 days' where id = n.id;
  perform pg_temp.ev(a, 45);
  perform pg_temp.ev(a, 120);
  assert (pg_temp.dr(a)).read_at is not null, 'after day 44: silence';
  assert (select count(*) from public.inbox_notices where owner_user_id = a and kind = 'develop_reminder') = 1, 'one row';

  -- The preference turns it off and resolves it.
  update public.profiles set notification_prefs = notification_prefs || '{"roll_reminders": false}' where user_id = a;
  perform pg_temp.ev(a, 121);
  assert (pg_temp.dr(a)).resolved_at is not null, 'preference off: resolved';

  -- Two rolls ring on their own days.
  perform pg_temp.waiting(b, t0);
  perform pg_temp.waiting(b, t0 + interval '5 days');
  perform pg_temp.ev(b, 14);
  update public.inbox_notices set read_at = t0 + interval '14 days' where id = (pg_temp.dr(b)).id;
  perform pg_temp.ev(b, 18);
  assert (pg_temp.dr(b)).read_at is not null, 'second roll not yet';
  perform pg_temp.ev(b, 19);
  assert (pg_temp.dr(b)).read_at is null, 'second roll rings on its day';

  -- At activation, a roll already 50 days in rings once.
  perform pg_temp.waiting(c, t0 - interval '50 days');
  perform pg_temp.ev(c, 0);
  assert (pg_temp.dr(c)).read_at is null and (pg_temp.dr(c)).shown_at is not null, 'rings once at activation';
  update public.inbox_notices set read_at = t0 where id = (pg_temp.dr(c)).id;
  perform pg_temp.ev(c, 1);
  assert (pg_temp.dr(c)).read_at is not null, 'no catch-up';

  -- A roll waiting without date counts from activation.
  rd := pg_temp.waiting(d, null);
  perform pg_temp.ev(d, 13);
  assert (pg_temp.dr(d)).id is null, 'no date: not yet on day 13';
  perform pg_temp.ev(d, 14);
  assert (pg_temp.dr(d)).read_at is null, 'no date: counts from activation';

  -- Leaving and coming back restarts the count.
  re := pg_temp.waiting(e, t0);
  perform pg_temp.ev(e, 9);
  update public.rolls set status = 'In Camera' where id = re;
  update public.rolls set status = 'To Develop' where id = re;
  update public.rolls set marked_to_develop_at = t0 + interval '10 days' where id = re;
  perform pg_temp.ev(e, 14);
  assert (pg_temp.dr(e)).id is null, 're-entry: day 14 of the old count is silent';
  perform pg_temp.ev(e, 24);
  assert (pg_temp.dr(e)).read_at is null, 're-entry: rings 14 days after coming back';
  update public.rolls set status = 'In Development' where id = re;
  perform pg_temp.ev(e, 25);
  assert (pg_temp.dr(e)).resolved_at is not null, 'sent to develop: resolved';
  assert not exists (select 1 from public.inbox_develop_rings where roll_id = re), 'ring count forgotten';

  -- Cleanup 90 days after resolving, read or not (Diego, 23-oct).
  insert into public.inbox_policy_notices (title_es, title_en, summary_es, summary_en, url, effective_on, published_by)
  values ('t', 't', 's', 's', 'https://analog-archive.com/privacy', '2025-01-01', g) returning id into pol;
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, read_at, resolved_at)
  values (g, 'missing_lab', pg_temp.buzon_roll(g, 'Developed'), t0, t0, t0 - interval '100 days', t0 - interval '89 days'),
         (g, 'missing_lab', pg_temp.buzon_roll(g, 'Developed'), t0, t0, null, t0 - interval '90 days'),
         (g, 'missing_lab', pg_temp.buzon_roll(g, 'Developed'), t0, t0, t0 - interval '400 days', null);
  -- A question answered from its card is resolved without being read.
  insert into public.inbox_notices (owner_user_id, kind, camera_id, detected_at, shown_at, resolved_at)
  values (g, 'camera_lens_question', pg_temp.buzon_camera(g), t0, t0, t0 - interval '91 days');
  insert into public.inbox_notices (owner_user_id, kind, policy_id, detected_at, shown_at, read_at, resolved_at)
  values (g, 'policy_change', pol, t0, t0, t0 - interval '400 days', t0);
  insert into public.inbox_notices (owner_user_id, kind, detected_at, shown_at, read_at, dismissed_at)
  values (g, 'backlog_incomplete', t0, t0, t0 - interval '400 days', t0 - interval '400 days');
  perform app_private.inbox_cleanup(g, t0);
  assert (select count(*) from public.inbox_notices where owner_user_id = g and kind = 'missing_lab') = 2,
         'resolved 89 days ago and open stay, resolved 90 days ago goes';
  assert not exists (select 1 from public.inbox_notices where owner_user_id = g and kind = 'missing_lab'
                     and resolved_at = t0 - interval '90 days'), 'the 90-day one went, unread';
  assert exists (select 1 from public.inbox_notices where owner_user_id = g and kind = 'missing_lab'
                 and resolved_at = t0 - interval '89 days'), 'read long ago but resolved 89 days ago stays';
  assert not exists (select 1 from public.inbox_notices where owner_user_id = g and kind = 'camera_lens_question'),
         'the answered question went too';
  assert exists (select 1 from public.inbox_notices where owner_user_id = g and kind = 'policy_change'), 'policy kept';
  assert exists (select 1 from public.inbox_notices where owner_user_id = g and kind = 'backlog_incomplete'),
         'dismissed group kept as a marker';

  -- Review Focus 2: the morning and the day are local.
  -- Kiritimati is UTC+14: 2026-11-01 17:59Z is 07:59 on Nov 2.
  perform app_private.inbox_tick('2026-11-01 17:59Z');
  assert (select last_evaluated_on from public.inbox_accounts where user_id = kiri) is null, 'Kiritimati 07:59: not yet';
  perform app_private.inbox_tick('2026-11-01 18:00Z');
  assert (select last_evaluated_on from public.inbox_accounts where user_id = kiri) = '2026-11-02', 'Kiritimati 08:00: evaluated';
  rk := pg_temp.buzon_roll(kiri, 'Developed');
  update public.rolls set created_at = '2026-11-01 18:30Z' where id = rk;
  perform app_private.inbox_tick('2026-11-01 19:00Z');
  assert not exists (select 1 from public.inbox_notices where roll_id = rk), 'same local day: not evaluated twice';
  perform app_private.inbox_tick('2026-11-02 18:00Z');
  assert exists (select 1 from public.inbox_notices where roll_id = rk), 'next local morning: evaluated';
  -- Los Angeles: marked on Oct 31 local (Nov 1 UTC); day 14 is Nov 14 local.
  -- Counting UTC dates it would wait until Nov 15.
  perform pg_temp.waiting(la, '2026-11-01 06:30Z');
  perform app_private.inbox_evaluate(la, '2026-11-14 07:30Z');
  assert (pg_temp.dr(la)).id is null, 'Nov 13 local: not yet';
  perform app_private.inbox_evaluate(la, '2026-11-14 16:00Z');
  assert (pg_temp.dr(la)).read_at is null, 'Nov 14 local: rings, a day before UTC would';

  -- The job exists.
  assert (select count(*) from cron.job where jobname = 'inbox_tick') = 1, 'cron job scheduled';
end $$;
