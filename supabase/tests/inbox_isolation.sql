-- Inbox isolation matrix (A, B, admin, pending, rejected, no session) and the
-- large-archive timing (Review Focus 4).
do $$
declare
  a uuid := pg_temp.buzon_user('iso_a');
  b uuid := pg_temp.buzon_user('iso_b');
  adm uuid := pg_temp.buzon_user('iso_adm');
  p uuid := pg_temp.buzon_user('iso_p', 'pending');
  rj uuid := pg_temp.buzon_user('iso_rj', 'rejected');
  v uuid := pg_temp.buzon_user('iso_v');
  cam_b bigint := pg_temp.buzon_camera(b);
  who uuid; tbl text; fn text; n int; nb uuid; t timestamptz; cams bigint[] := '{}';
  pub constant text := 'select public.inbox_publish_policy(''t'', ''t'', ''s'', ''s'', ''https://analog-archive.com/x'', current_date + 9)';
begin
  -- Each account has a bit of everything.
  update public.profiles set created_at = now() - interval '1 day' where user_id in (a, b, adm);
  perform pg_temp.buzon_admin(adm);
  foreach who in array array[a, b] loop
    insert into public.inbox_accounts (user_id, activated_at) values (who, now());
    insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at)
    values (who, 'missing_lab', pg_temp.buzon_roll(who, 'Developed'), now(), now(), now());
    insert into public.inbox_notices (owner_user_id, kind, detected_at, shown_at, rang_at)
    values (who, 'backlog_incomplete', now(), now(), now());
    insert into public.inbox_seen_keys (user_id, key) values (who, 'news:x');
    insert into public.inbox_develop_rings (roll_id, owner_user_id, started_at)
    values (pg_temp.buzon_roll(who, 'To Develop'), who, now()) on conflict do nothing;
  end loop;
  perform pg_temp.como(adm);
  perform public.inbox_publish_policy('t', 't', 's', 's', 'https://analog-archive.com/x', current_date + 9);
  perform pg_temp.yo();
  select id into nb from public.inbox_notices where owner_user_id = b and kind = 'missing_lab';

  -- Direct reads: only your own rows; policies only for approved accounts.
  perform pg_temp.como(a);
  foreach tbl in array array['inbox_notices', 'inbox_develop_rings'] loop
    execute format('select count(*) from public.%I where owner_user_id <> %L', tbl, a) into n;
    assert n = 0, format('A reads only its own %s', tbl);
  end loop;
  assert (select count(*) from public.inbox_accounts where user_id <> a) = 0, 'A reads only its own account';
  assert (select count(*) from public.inbox_seen_keys where user_id <> a) = 0, 'A reads only its own seen keys';
  assert (select count(*) from public.inbox_policy_notices) >= 1, 'A reads policies';
  assert (select count(*) from public.inbox_notices) = 3, 'A sees its 3 notices';
  foreach who in array array[p, rj] loop
    perform pg_temp.como(who);
    foreach tbl in array array['inbox_notices', 'inbox_develop_rings', 'inbox_accounts',
                               'inbox_seen_keys', 'inbox_policy_notices'] loop
      execute format('select count(*) from public.%I', tbl) into n;
      assert n = 0, format('pending or rejected reads nothing from %s', tbl);
    end loop;
  end loop;
  perform pg_temp.como(null);
  foreach tbl in array array['inbox_notices', 'inbox_develop_rings', 'inbox_accounts',
                             'inbox_seen_keys', 'inbox_policy_notices'] loop
    perform pg_temp.espera_error(format('select count(*) from public.%I', tbl), '42501');
  end loop;
  perform pg_temp.yo();

  -- The isolation check catches a broken policy: drop the owner condition and it fails.
  begin
    alter policy inbox_notices_select_own on public.inbox_notices to authenticated
      using (exists (select 1 from public.profiles pr where pr.user_id = (select auth.uid()) and pr.status = 'approved'));
    perform pg_temp.como(a);
    if (select count(*) from public.inbox_notices where owner_user_id <> a) = 0 then
      raise exception 'mutation not detected';
    end if;
    raise exception 'zz_mut';
  exception when others then
    if sqlerrm <> 'zz_mut' then raise; end if;
  end;
  perform pg_temp.yo();
  perform pg_temp.como(a);
  assert (select count(*) from public.inbox_notices where owner_user_id <> a) = 0, 'policy restored';
  perform pg_temp.yo();

  -- Functions: your own works, the other account is never touched.
  perform pg_temp.como(a);
  assert not exists (select 1 from jsonb_array_elements(public.inbox_list() -> 'notices') x
                     where (x ->> 'id')::uuid not in (select id from public.inbox_notices)), 'list has only A notices';
  assert public.inbox_mark(array[nb], true) = 0, 'cannot mark B';
  perform public.inbox_mark_all_read();
  perform public.inbox_dismiss_backlog();
  perform pg_temp.espera_error(format('select public.inbox_answer_camera_lens(%s, false)', cam_b), 'P1204');
  perform pg_temp.espera_error('select public.inbox_mark_admin(true)', 'P1205');
  perform pg_temp.espera_error(pub, 'P1205');
  perform pg_temp.yo();
  assert (select read_at from public.inbox_notices where id = nb) is null, 'B notice unread';
  assert (select dismissed_at from public.inbox_notices where owner_user_id = b and kind = 'backlog_incomplete') is null,
         'B group not dismissed';
  assert (select supports_interchangeable_lenses and lens_setup_confirmed_at is null from public.cameras where id = cam_b),
         'B camera untouched';
  perform pg_temp.como(adm);
  perform public.inbox_mark_admin(true);
  perform pg_temp.yo();

  -- Pending, rejected and no session, on every public function.
  foreach fn in array array['select public.inbox_list()', 'select public.inbox_unread_count()',
                            'select public.inbox_mark(array[gen_random_uuid()], true)', 'select public.inbox_mark_all_read()',
                            'select public.inbox_dismiss_backlog()', 'select public.inbox_mark_admin(true)',
                            'select public.inbox_answer_camera_lens(1, true)',
                            $q$select public.inbox_mark_seen(array['news:x'])$q$, pub] loop
    foreach who in array array[p, rj] loop
      perform pg_temp.como(who);
      perform pg_temp.espera_error(fn, 'P1202');
    end loop;
    perform pg_temp.como(null);
    perform pg_temp.espera_error(fn, '42501');
    perform pg_temp.yo();
  end loop;

  -- Review Focus 4: 300 rolls out of camera, 10 cameras, 36 frames each.
  for n in 1..10 loop
    cams := cams || pg_temp.buzon_camera(v, case when n % 2 = 0 then 'Mount' end);
  end loop;
  insert into public.rolls (owner_user_id, code, client_uuid, status, camera_id)
  select v, 'V' || g, gen_random_uuid(), (array['Developed', 'Archived', 'To Develop'])[1 + g % 3], cams[1 + g % 10]
  from generate_series(1, 300) g;
  insert into public.roll_exposures (roll_id, frame_number, lens_source, lens_snapshot)
  select r.id, f, case when r.id % 2 = 0 then 'roll_default' end,
         case when r.id % 2 = 0 then '{"version": 1, "display_name": "Test 50"}'::jsonb end
  from public.rolls r, generate_series(1, 36) f
  where r.owner_user_id = v;
  insert into public.inbox_accounts (user_id, activated_at) values (v, now() - interval '1 day');
  t := clock_timestamp();
  perform app_private.inbox_evaluate(v, now() + interval '4 days');
  assert clock_timestamp() - t < interval '2 seconds',
         format('evaluate took %s', clock_timestamp() - t);
  assert (select count(*) from public.inbox_notices where owner_user_id = v) > 0, 'large archive produced notices';
  perform pg_temp.como(v);
  t := clock_timestamp();
  perform public.inbox_list();
  assert clock_timestamp() - t < interval '2 seconds', format('list took %s', clock_timestamp() - t);
  perform pg_temp.yo();
end $$;
