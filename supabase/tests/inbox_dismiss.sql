-- Deleting read inbox notices: only read ones, only your own, and a deleted
-- notice comes back only when there is something new. Run after
-- inbox_helpers.sql, inside BEGIN / ROLLBACK.
-- T0 = 2026-11-01 15:00Z (09:00 in Mexico City).
create function pg_temp.ev(p_uid uuid, p_days numeric) returns void language sql as $$
  select app_private.inbox_evaluate(p_uid, '2026-11-01 15:00Z'::timestamptz + make_interval(secs => p_days * 86400));
$$;

create function pg_temp.notice(p_uid uuid, p_kind text) returns public.inbox_notices language sql as $$
  select * from public.inbox_notices n where n.owner_user_id = p_uid and n.kind = p_kind limit 1;
$$;

create function pg_temp.dismiss(p_uid uuid, p_ids uuid[]) returns integer language plpgsql as $$
declare v integer;
begin
  perform pg_temp.como(p_uid);
  v := public.inbox_dismiss(p_ids);
  perform pg_temp.yo();
  return v;
end $$;

do $$
declare
  t0 timestamptz := '2026-11-01 15:00Z';
  a uuid := pg_temp.buzon_user('dis_a');
  b uuid := pg_temp.buzon_user('dis_b');
  d uuid := pg_temp.buzon_user('dis_d');
  g uuid := pg_temp.buzon_user('dis_g');
  adm uuid := pg_temp.buzon_user('dis_adm');
  n1 uuid; n2 uuid; n3 uuid; nd uuid; ng uuid; np uuid;
  r bigint; lab bigint; pol uuid; v integer;
  ids uuid[];
begin
  insert into public.inbox_accounts (user_id, activated_at)
  select u, now() - interval '10 days' from unnest(array[a, b, g, adm]) u;
  insert into public.inbox_accounts (user_id, activated_at) values (d, t0);

  -- Three plain notices for A: two read, one unread.
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at, read_at)
  values (a, 'missing_lab', pg_temp.buzon_roll(a, 'Developed'), now(), now(), now(), now()) returning id into n1;
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at, read_at)
  values (a, 'missing_lab', pg_temp.buzon_roll(a, 'Developed'), now(), now(), now(), now()) returning id into n2;
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at)
  values (a, 'missing_lab', pg_temp.buzon_roll(a, 'Developed'), now(), now(), now()) returning id into n3;

  -- isolation: B cannot delete A's notices.
  assert pg_temp.dismiss(b, array[n1]) = 0, 'isolation: nothing changed';
  assert (select dismissed_at is null from public.inbox_notices where id = n1), 'isolation: still there';

  -- only_read.
  assert pg_temp.dismiss(a, array[n1, n3]) = 1, 'only_read: one changed';
  assert (select dismissed_at is not null from public.inbox_notices where id = n1), 'only_read: read one gone';
  assert (select dismissed_at is null from public.inbox_notices where id = n3), 'only_read: unread one stays';

  -- dismiss_read: the remaining read one goes, the unread stays.
  perform pg_temp.como(a);
  v := public.inbox_dismiss_read();
  perform pg_temp.yo();
  assert v = 1, 'dismiss_read: one more, got ' || v;
  assert (select dismissed_at is not null from public.inbox_notices where id = n2), 'dismiss_read: read gone';
  assert (select dismissed_at is null from public.inbox_notices where id = n3), 'dismiss_read: unread stays';
  assert not exists (select 1 from jsonb_array_elements(app_private.inbox_payload(a, now()) -> 'notices') e
                     where e ->> 'id' in (n1::text, n2::text)), 'deleted ones leave the list';

  -- too_many and anon.
  select array_agg(gen_random_uuid()) into ids from generate_series(1, 501);
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.inbox_dismiss(%L::uuid[])', ids), 'P1203');
  perform pg_temp.espera_error('select public.inbox_dismiss(null)', 'P1203');
  perform pg_temp.como(null);
  perform pg_temp.espera_error(format('select public.inbox_dismiss(array[%L]::uuid[])', n3), '42501');
  perform pg_temp.espera_error('select public.inbox_dismiss_read()', '42501');
  perform pg_temp.yo();

  -- policy_needs_open: read (mark all) but never opened stays; opened goes; the row is kept.
  update public.profiles set created_at = now() - interval '1 day' where user_id in (a, adm);
  perform pg_temp.buzon_admin(adm);
  perform pg_temp.como(adm);
  pol := public.inbox_publish_policy('Cambios', 'Changes', 'Resumen', 'Summary',
           'https://analog-archive.com/privacy', (now() at time zone 'America/Mexico_City')::date + 5);
  perform pg_temp.yo();
  np := (select id from public.inbox_notices where owner_user_id = a and policy_id = pol);
  update public.inbox_notices set read_at = now() where id = np;
  assert pg_temp.dismiss(a, array[np]) = 0, 'policy: read but not opened stays';
  update public.inbox_notices set first_opened_at = now() where id = np;
  assert pg_temp.dismiss(a, array[np]) = 1, 'policy: opened can go';
  perform app_private.inbox_cleanup(a, now() + interval '200 days');
  assert exists (select 1 from public.inbox_notices where id = np), 'policy: row kept as proof';

  -- develop_returns_on_ring.
  r := pg_temp.buzon_roll(d, 'To Develop');
  update public.rolls set marked_to_develop_at = t0 where id = r;
  perform pg_temp.ev(d, 14);
  nd := (pg_temp.notice(d, 'develop_reminder')).id;
  update public.inbox_notices set read_at = t0 + interval '14 days' where id = nd;
  assert pg_temp.dismiss(d, array[nd]) = 1, 'develop: deleted';
  perform pg_temp.ev(d, 30);
  assert (pg_temp.notice(d, 'develop_reminder')).dismissed_at is not null, 'develop: day 30 still deleted';
  perform pg_temp.ev(d, 44);
  assert (pg_temp.notice(d, 'develop_reminder')).dismissed_at is null, 'develop: day 44 rings again';
  assert (pg_temp.notice(d, 'develop_reminder')).read_at is null, 'develop: and unread';

  -- gap_stays_gone.
  r := pg_temp.buzon_roll(g, 'Developed');
  perform app_private.inbox_evaluate(g, now());
  perform app_private.inbox_evaluate(g, now() + interval '3 days');
  ng := (select id from public.inbox_notices where owner_user_id = g and kind = 'missing_lab' and roll_id = r);
  assert (select shown_at is not null from public.inbox_notices where id = ng), 'gap: shown';
  update public.inbox_notices set read_at = now() where id = ng;
  assert pg_temp.dismiss(g, array[ng]) = 1, 'gap: deleted';
  perform app_private.inbox_resolve(g, now() + interval '4 days');
  assert (select dismissed_at is not null from public.inbox_notices where id = ng), 'gap: still deleted while missing';
  perform app_private.inbox_cleanup(g, now() + interval '120 days');
  assert exists (select 1 from public.inbox_notices where id = ng), 'gap: cleanup keeps it while missing';
  perform app_private.inbox_evaluate(g, now() + interval '5 days');
  assert (select count(*) from public.inbox_notices where owner_user_id = g and kind = 'missing_lab' and roll_id = r) = 1,
         'gap: no second notice';
  assert (select dismissed_at is not null from public.inbox_notices where id = ng), 'gap: still deleted after evaluate';

  -- gap_returns_when_new: fixed, then missing again.
  insert into public.labs (name) values ('Lab buzon dismiss') returning id into lab;
  update public.rolls set dev_lab_id = lab where id = r;
  perform app_private.inbox_resolve(g, now() + interval '6 days');
  assert (select resolved_at is not null from public.inbox_notices where id = ng), 'gap: resolved once fixed';
  update public.rolls set dev_lab_id = null where id = r;
  perform app_private.inbox_resolve(g, now() + interval '7 days');
  assert (select dismissed_at is null and read_at is null and resolved_at is null
          from public.inbox_notices where id = ng), 'gap: back when missing again';
end $$;
