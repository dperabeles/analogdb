-- Push outbox (ANA-74): what rings in the inbox is queued for the phone, and
-- the FCM token only ever belongs to one account. Run after inbox_helpers.sql,
-- inside BEGIN / ROLLBACK.
-- T0 = 2026-11-01 15:00Z (09:00 in Mexico City).
create function pg_temp.ev(p_uid uuid, p_days numeric) returns void language sql as $$
  select app_private.inbox_evaluate(p_uid, '2026-11-01 15:00Z'::timestamptz + make_interval(secs => p_days * 86400));
$$;

create function pg_temp.queued(p_uid uuid, p_kind text default null) returns bigint language sql as $$
  select count(*) from app_private.push_outbox o
  where o.user_id = p_uid and (p_kind is null or o.kind = p_kind);
$$;

do $$
declare
  t0 timestamptz := '2026-11-01 15:00Z';
  a uuid := pg_temp.buzon_user('push_a');
  b uuid := pg_temp.buzon_user('push_b');
  g uuid := pg_temp.buzon_user('push_g');
  off uuid := pg_temp.buzon_user('push_off');
  adm uuid := pg_temp.buzon_user('push_adm');
  r bigint;
  pol uuid;
begin
  insert into public.inbox_accounts (user_id, activated_at)
  select u, t0 from unnest(array[a, b, g, off, adm]) u;

  -- enqueue_on_ring: a roll waiting 14 days rings once and queues once.
  r := pg_temp.buzon_roll(a, 'To Develop');
  update public.rolls set marked_to_develop_at = t0 where id = r;
  perform pg_temp.ev(a, 14);
  assert pg_temp.queued(a, 'develop_reminder') = 1, 'enqueue_on_ring';

  -- no_double_enqueue: same day again stays at 1; day 44 rings again.
  perform pg_temp.ev(a, 14.1);
  assert pg_temp.queued(a, 'develop_reminder') = 1, 'no_double_enqueue (same day)';
  perform pg_temp.ev(a, 44);
  assert pg_temp.queued(a, 'develop_reminder') = 2, 'no_double_enqueue (day 44 rings again)';

  -- gaps_do_not_enqueue: data-gap notices stay in the inbox only.
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at)
  values (g, 'missing_lab', pg_temp.buzon_roll(g, 'Developed'), now(), now(), now());
  assert pg_temp.queued(g) = 0, 'gaps_do_not_enqueue';

  -- prefs_off: with roll reminders off nothing rings, so nothing is queued.
  update public.profiles set notification_prefs = notification_prefs || '{"roll_reminders": false}'
   where user_id = off;
  r := pg_temp.buzon_roll(off, 'To Develop');
  update public.rolls set marked_to_develop_at = t0 where id = r;
  perform pg_temp.ev(off, 14);
  assert pg_temp.queued(off) = 0, 'prefs_off';

  -- policy_enqueues: publishing queues one policy_change per earlier account.
  update public.profiles set created_at = now() - interval '1 day' where user_id in (a, b, adm);
  perform pg_temp.buzon_admin(adm);
  perform pg_temp.como(adm);
  pol := public.inbox_publish_policy('Cambios', 'Changes', 'Resumen', 'Summary',
           'https://analog-archive.com/privacy', (now() at time zone 'America/Mexico_City')::date + 5);
  perform pg_temp.yo();
  assert pg_temp.queued(a, 'policy_change') = 1, 'policy_enqueues (a)';
  assert pg_temp.queued(b, 'policy_change') = 1, 'policy_enqueues (b)';

  -- token_moves: the same phone registered by B leaves A without it.
  perform pg_temp.como(a);
  perform public.register_push_token('tok-1', 'ios');
  perform pg_temp.como(b);
  perform public.register_push_token('tok-1', 'ios');
  perform pg_temp.yo();
  assert (select fcm_token from public.profiles where user_id = a) is null, 'token_moves (a lost it)';
  assert (select fcm_token from public.profiles where user_id = b) = 'tok-1', 'token_moves (b has it)';
  assert (select fcm_platform from public.profiles where user_id = b) = 'ios', 'token_moves (platform)';

  -- B cannot read A's token: profiles stay self-only.
  perform pg_temp.como(a);
  perform public.register_push_token('tok-a', 'android');
  perform pg_temp.como(b);
  assert (select count(*) from public.profiles where user_id = a) = 0, 'b cannot see a';
  perform pg_temp.yo();

  -- no_direct_write: the token is only written through the function.
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format($q$update public.profiles set fcm_token = 'x' where user_id = %L$q$, a), '42501');
  -- outbox_hidden: the queue is not readable by users.
  perform pg_temp.espera_error('select count(*) from app_private.push_outbox', '42501');

  -- bad_input.
  perform pg_temp.espera_error($q$select public.register_push_token('', 'ios')$q$, 'P1203');
  perform pg_temp.espera_error($q$select public.register_push_token('tok', 'web')$q$, 'P1203');
  perform pg_temp.espera_error(format($q$select public.register_push_token(%L, 'ios')$q$, repeat('x', 4097)), 'P1203');

  -- clear.
  perform public.clear_push_token();
  perform pg_temp.yo();
  assert (select fcm_token from public.profiles where user_id = a) is null, 'clear (token)';
  assert (select fcm_platform from public.profiles where user_id = a) is null, 'clear (platform)';

  -- anon cannot register.
  perform pg_temp.como(null);
  perform pg_temp.espera_error($q$select public.register_push_token('tok-z', 'ios')$q$, '42501');
  perform pg_temp.yo();

  -- cascade: deleting the account removes its queued rows.
  assert pg_temp.queued(a) > 0, 'cascade (precondition)';
  delete from auth.users where id = a;
  assert pg_temp.queued(a) = 0, 'cascade';
end $$;
