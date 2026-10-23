-- Inbox base: tables, privileges, the new camera column and local dates.
do $$
declare
  a uuid := pg_temp.buzon_user('base_a');
  b uuid := pg_temp.buzon_user('base_b');
  p uuid := pg_temp.buzon_user('base_p', 'pending');
  tokyo uuid := pg_temp.buzon_user('base_tokyo', 'approved', 'Asia/Tokyo');
  badtz uuid := pg_temp.buzon_user('base_badtz', 'approved', 'Mars/Olympus');
  cam bigint := pg_temp.buzon_camera(a);
  rb bigint := pg_temp.buzon_roll(b, 'Developed');
begin
  assert to_regclass('public.inbox_notices') is not null, 'tables exist';

  -- Rows written by the runner, one per table, for A and for B.
  insert into public.inbox_accounts (user_id, activated_at) values (a, now()), (b, now());
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at)
  values (b, 'missing_lab', rb, now());
  insert into public.inbox_seen_keys (user_id, key) values (b, 'news:x');
  insert into public.inbox_develop_rings (roll_id, owner_user_id, started_at) values (rb, b, now());
  insert into public.inbox_policy_notices (title_es, title_en, summary_es, summary_en, url, effective_on, published_by)
  values ('t', 't', 's', 's', 'https://analog-archive.com/privacy', current_date + 5, a);

  perform pg_temp.como(a);
  assert (select count(*) from public.inbox_accounts) = 1, 'A sees only its own account row';
  assert (select count(*) from public.inbox_notices) = 0, 'A cannot read B notices';
  assert (select count(*) from public.inbox_seen_keys) = 0, 'A cannot read B seen keys';
  assert (select count(*) from public.inbox_develop_rings) = 0, 'A cannot read B rings';
  assert (select count(*) from public.inbox_policy_notices) = 1, 'approved accounts read policies';
  perform pg_temp.espera_error('insert into public.inbox_seen_keys (user_id, key) values (auth.uid(), ''x'')', '42501');
  perform pg_temp.espera_error('update public.inbox_accounts set admin_read_at = now()', '42501');
  perform pg_temp.yo();

  perform pg_temp.como(b);
  assert (select count(*) from public.inbox_notices) = 1, 'B reads its own notice';
  perform pg_temp.yo();

  perform pg_temp.como(p);
  assert (select count(*) from public.inbox_policy_notices) = 0, 'pending accounts read no policies';
  perform pg_temp.espera_error('select app_private.inbox_caller()', '42501');
  perform pg_temp.yo();

  perform pg_temp.como(null);
  perform pg_temp.espera_error('select count(*) from public.inbox_policy_notices', '42501');
  perform pg_temp.yo();

  -- inbox_caller, called as the definer functions will call it.
  perform set_config('request.jwt.claim.sub', p::text, true);
  perform pg_temp.espera_error('select app_private.inbox_caller()', 'P1202');
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  perform pg_temp.espera_error('select app_private.inbox_caller()', 'P1201');
  perform set_config('request.jwt.claim.sub', a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  assert app_private.inbox_caller() = a, 'approved caller';
  perform pg_temp.yo();

  -- The old column did not change; the new one starts empty.
  assert (select data_type || column_default || is_nullable from information_schema.columns
          where table_schema = 'public' and table_name = 'cameras'
            and column_name = 'supports_interchangeable_lenses') = 'booleantrueNO',
         'supports_interchangeable_lenses unchanged';
  assert (select lens_setup_confirmed_at from public.cameras where id = cam) is null, 'new column starts null';

  -- Local dates.
  assert app_private.inbox_local_date(tokyo, '2026-10-22 16:00Z') = '2026-10-23', 'Tokyo is ahead';
  assert app_private.inbox_local_date(a, '2026-10-22 03:00Z') = '2026-10-21', 'no zone: Mexico City';
  assert app_private.inbox_local_date(badtz, '2026-10-22 03:00Z') = '2026-10-21', 'invalid zone: Mexico City';

  -- Identity: the same notice twice is refused.
  begin
    insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at)
    values (b, 'missing_lab', rb, now());
    raise exception 'duplicate notice accepted';
  exception when unique_violation then null;
  end;
end $$;
