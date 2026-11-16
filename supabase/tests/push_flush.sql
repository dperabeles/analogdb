-- Push flush (ANA-74): claiming queued rows, completing them, the flush call
-- and the 90-day cleanup. Run after inbox_helpers.sql, inside BEGIN / ROLLBACK.
-- T0 = 2026-11-01 15:00Z (09:00 in Mexico City).
create function pg_temp.ev(p_uid uuid, p_days numeric) returns void language sql as $$
  select app_private.inbox_evaluate(p_uid, '2026-11-01 15:00Z'::timestamptz + make_interval(secs => p_days * 86400));
$$;

create function pg_temp.ring(p_uid uuid) returns uuid language plpgsql as $$
declare r bigint := pg_temp.buzon_roll(p_uid, 'To Develop');
begin
  update public.rolls set marked_to_develop_at = '2026-11-01 15:00Z' where id = r;
  perform pg_temp.ev(p_uid, 14);
  return (select o.id from app_private.push_outbox o where o.user_id = p_uid order by o.created_at desc limit 1);
end $$;

create function pg_temp.http_calls() returns bigint language sql as $$
  select count(*) from net.http_request_queue;
$$;

do $$
declare
  t0 timestamptz := '2026-11-01 15:00Z';
  t14 timestamptz := t0 + interval '14 days';
  a uuid := pg_temp.buzon_user('fl_a');
  en uuid := pg_temp.buzon_user('fl_en');
  tk uuid := pg_temp.buzon_user('fl_tk', 'approved', 'Asia/Tokyo');
  bat uuid := pg_temp.buzon_user('fl_bat');
  adm uuid := pg_temp.buzon_user('fl_adm');
  oa uuid; oen uuid; otk uuid; nid uuid; c record; n int; calls bigint; st text;
begin
  insert into public.inbox_accounts (user_id, activated_at)
  select u, t0 from unnest(array[a, en, tk, bat, adm]) u;
  update auth.users set raw_user_meta_data = raw_user_meta_data || '{"locale": "en-US"}' where id = en;
  -- Flush must be configurable per environment; start from "not configured".
  delete from public.private_app_config where config_key in ('push_flush_url', 'push_flush_secret');

  oa := pg_temp.ring(a);
  oen := pg_temp.ring(en);

  -- claim_basic: fields come from the account, the reminder count from the inbox.
  select * into c from public.push_claim(100, t14 + interval '1 hour') where outbox_id = oa;
  assert c.outbox_id is not null, 'claim_basic: claimed';
  assert c.kind = 'develop_reminder' and c.develop_count = 1, 'claim_basic: kind and count';
  assert c.locale = 'es' and c.zone = 'America/Mexico_City' and c.legal_updates, 'claim_basic: defaults';
  select * into c from public.push_claim(100, t14 + interval '1 hour') where outbox_id = oen;
  assert c.outbox_id is null, 'lease: already claimed by the first call';
  select * into c from public.push_claim(100, t14 + interval '1 hour' + interval '3 minutes') where outbox_id = oen;
  assert c.locale = 'en-US', 'lease expires after 2 minutes; locale from metadata';

  -- hours: 16:00Z is 01:00 in Tokyo, so the row waits; stale rows are handed out to be skipped.
  otk := pg_temp.ring(tk);
  assert not exists (select 1 from public.push_claim(100, t14 + interval '1 hour') where outbox_id = otk), 'hours: Tokyo at night waits';
  assert exists (select 1 from public.push_claim(100, t14 + interval '8 hours') where outbox_id = otk), 'hours: Tokyo at 08:00 is claimed';
  update app_private.push_outbox set claimed_at = null where id = otk;
  assert exists (select 1 from public.push_claim(100, t14 + interval '2 days 1 hour') where outbox_id = otk), 'stale rows are claimed even at night';

  -- batch: 150 pending rows, a batch of 100 leaves 50 untouched.
  nid := (select n.id from public.inbox_notices n where n.owner_user_id = a and n.kind = 'develop_reminder');
  insert into app_private.push_outbox (user_id, notice_id, kind, rang_at, created_at)
  select bat, nid, 'develop_reminder', t14 + make_interval(secs => i), t14 + make_interval(secs => i)
  from generate_series(1, 150) i;
  select count(*) into n from public.push_claim(100, t14 + interval '1 hour 10 minutes') x where x.user_id = bat;
  assert n = 100, 'batch: 100 claimed, got ' || n;
  assert (select count(*) from app_private.push_outbox where user_id = bat and claimed_at is null) = 50, 'batch: 50 left';
  delete from app_private.push_outbox where user_id = bat;

  -- complete_sent.
  st := public.push_complete(oa, 'sent', 200, 'Tu siguiente revelado.', 'Tienes 1 film por revelar.', false, null);
  assert st = 'sent', 'complete_sent: status';
  assert (select status = 'sent' and sent_at is not null from app_private.push_outbox where id = oa), 'complete_sent: row';
  assert (select count(*) from public.push_log where user_id = a and status = 'sent') = 1, 'complete_sent: log';

  -- complete_retry: two retries go back to pending, the third fails.
  assert public.push_complete(oen, 'retry', 503, 'Your next development.', 'You have 1 film to develop.', false, null) = 'pending', 'retry 1';
  assert (select claimed_at is null and attempts = 1 from app_private.push_outbox where id = oen), 'retry 1: released';
  assert public.push_complete(oen, 'retry', 503, 'x', 'y', false, null) = 'pending', 'retry 2';
  assert public.push_complete(oen, 'retry', 503, 'x', 'y', false, null) = 'failed', 'retry 3 fails';
  assert (select count(*) from public.push_log where user_id = en and status = 'failed') = 1, 'retry: one failed log line';

  -- release (outside hours, decided by the function) changes nothing but the lease.
  update app_private.push_outbox set claimed_at = now(), attempts = 0 where id = otk;
  assert public.push_complete(otk, 'release', null, null, null, false, null) = 'pending', 'release';
  assert (select claimed_at is null and attempts = 0 from app_private.push_outbox where id = otk), 'release: untouched';

  -- clear only the same token.
  update public.profiles set fcm_token = 'new-tok', fcm_platform = 'ios' where user_id = tk;
  perform public.push_complete(otk, 'failed', 404, 'x', 'y', true, 'old-tok');
  assert (select fcm_token from public.profiles where user_id = tk) = 'new-tok', 'clear: different token kept';
  update app_private.push_outbox set status = 'pending' where id = otk;
  perform public.push_complete(otk, 'failed', 404, 'x', 'y', true, 'new-tok');
  assert (select fcm_token from public.profiles where user_id = tk) is null, 'clear: same token removed';

  -- opted_out and skipped.
  update app_private.push_outbox set status = 'pending' where id = otk;
  assert public.push_complete(otk, 'opted_out', null, 'Cambios', 'Resumen', false, null) = 'skipped', 'opted_out';
  assert (select count(*) from public.push_log where user_id = tk and status = 'opted_out') = 1, 'opted_out: logged';
  update app_private.push_outbox set status = 'pending' where id = otk;
  assert public.push_complete(otk, 'skipped', null, null, null, false, null) = 'skipped', 'skipped';
  perform pg_temp.espera_error(format($q$select public.push_complete(%L, 'bogus', null, null, null, false, null)$q$, otk), 'P1203');

  -- not_for_authenticated.
  perform pg_temp.como(a);
  perform pg_temp.espera_error('select * from public.push_claim(1)', '42501');
  perform pg_temp.espera_error(format($q$select public.push_complete(%L, 'sent', 200, 'x', 'y', false, null)$q$, oa), '42501');
  perform pg_temp.yo();

  -- flush: a no-op without configuration, one call with it.
  calls := pg_temp.http_calls();
  perform app_private.push_flush();
  assert pg_temp.http_calls() = calls, 'flush_without_config_is_noop';
  insert into public.private_app_config (config_key, config_value) values
    ('push_flush_url', 'https://example.invalid/functions/v1/send-push'), ('push_flush_secret', 'test-secret');
  perform app_private.push_flush();
  assert pg_temp.http_calls() = calls + 1, 'flush with config posts once';

  -- tick and publish flush too.
  calls := pg_temp.http_calls();
  perform app_private.inbox_tick(t14 + interval '30 days');
  assert pg_temp.http_calls() = calls + 1, 'tick flushes';
  update public.profiles set created_at = now() - interval '1 day' where user_id = adm;
  perform pg_temp.buzon_admin(adm);
  perform pg_temp.como(adm);
  perform public.inbox_publish_policy('Cambios', 'Changes', 'Resumen', 'Summary',
            'https://analog-archive.com/privacy', (now() at time zone 'America/Mexico_City')::date + 5);
  perform pg_temp.yo();
  assert pg_temp.http_calls() = calls + 2, 'publish flushes';

  -- cleanup_90d.
  update app_private.push_outbox set created_at = now() - interval '91 days' where id = oa;
  update app_private.push_outbox set created_at = now() - interval '89 days', status = 'sent' where id = oen;
  update public.push_log set created_at = now() - interval '91 days' where user_id = a;
  perform app_private.push_cleanup(now());
  assert not exists (select 1 from app_private.push_outbox where id = oa), 'cleanup: 91 days gone';
  assert exists (select 1 from app_private.push_outbox where id = oen), 'cleanup: 89 days kept';
  assert (select count(*) from public.push_log where user_id = a) = 0, 'cleanup: old log gone';
  assert (select count(*) from public.push_log where user_id = en) = 1, 'cleanup: recent log kept';
end $$;
