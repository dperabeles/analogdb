-- Review minors closed on 23-oct, one block each: the policy proof cannot be
-- deleted, a client cannot restart the to-develop count, a roll with no
-- creation date still counts, a missing or bad zone falls back to Mexico City
-- through the hourly tick, and the admin block says when the account is not an
-- admin. The 90-day cleanup rule is in inbox_reminders.sql.

-- The policy row keeps the proof that it was seen.
do $$
declare
  a uuid := pg_temp.buzon_user('mn_pa');
  adm uuid := pg_temp.buzon_user('mn_padm');
  pol uuid;
begin
  insert into public.inbox_policy_notices (title_es, title_en, summary_es, summary_en, url, effective_on, published_by)
  values ('t', 't', 's', 's', 'https://analog-archive.com/privacy', '2025-01-01', adm) returning id into pol;
  insert into public.inbox_notices (owner_user_id, kind, policy_id, detected_at, shown_at, read_at, first_opened_at)
  values (a, 'policy_change', pol, now(), now(), now(), '2026-10-01');
  begin
    delete from public.inbox_policy_notices where id = pol;
    raise exception 'a policy with notices was deleted';
  exception when foreign_key_violation then null;
  end;
  assert exists (select 1 from public.inbox_notices where policy_id = pol and first_opened_at = '2026-10-01'),
         'the proof survives';
end $$;

-- A client never restarts the count while the roll stays in To Develop.
do $$
declare
  a uuid := pg_temp.buzon_user('mn_da');
  t0 timestamptz := now();
  r bigint := pg_temp.buzon_roll(a, 'To Develop');
begin
  update public.rolls set marked_to_develop_at = '2026-01-01' where id = r;
  perform pg_temp.como(a);
  update public.rolls set marked_to_develop_at = now() where id = r;
  update public.rolls set status = 'To Develop', marked_to_develop_at = now(), notes = 'reintento' where id = r;
  perform pg_temp.yo();
  assert (select marked_to_develop_at from public.rolls where id = r) = '2026-01-01',
         'a client rewrite keeps the date';
  perform pg_temp.como(a);
  update public.rolls set status = 'Developed' where id = r;
  update public.rolls set status = 'To Develop' where id = r;
  perform pg_temp.yo();
  assert (select marked_to_develop_at from public.rolls where id = r) >= t0, 'coming back in restamps';
end $$;

-- A roll without a creation date counts as old instead of disappearing.
do $$
declare
  a uuid := pg_temp.buzon_user('mn_ca');
  ro bigint;
begin
  insert into public.inbox_accounts (user_id, activated_at) values (a, now() - interval '1 day');
  ro := pg_temp.buzon_roll(a, 'Developed');
  update public.rolls set created_at = null where id = ro;
  assert exists (select 1 from app_private.inbox_roll_gaps(a) g
                 where g.roll_id = ro and g.kind = 'missing_camera' and g.is_old),
         'no creation date is old';
end $$;

-- Missing and bad zones fall back to Mexico City (UTC-6) in the hourly tick.
do $$
declare
  nz uuid := pg_temp.buzon_user('mn_nz');
  bz uuid := pg_temp.buzon_user('mn_bz', 'approved', 'Mars/Olympus');
begin
  insert into public.inbox_accounts (user_id, activated_at) values
    (nz, now() - interval '30 days'), (bz, now() - interval '30 days');
  perform app_private.inbox_tick('2026-11-02 13:59Z');
  assert (select count(*) from public.inbox_accounts where user_id in (nz, bz) and last_evaluated_on is not null) = 0,
         '07:59 in Mexico City is too early';
  perform app_private.inbox_tick('2026-11-02 14:00Z');
  assert (select count(*) from public.inbox_accounts
          where user_id in (nz, bz) and last_evaluated_on = '2026-11-02' and last_error is null) = 2,
         '08:00 in Mexico City evaluates both';
end $$;

-- The admin block says which case it is.
do $$
declare
  a uuid := pg_temp.buzon_user('mn_aa');
  adm uuid := pg_temp.buzon_user('mn_aadm');
  l jsonb;
begin
  perform pg_temp.buzon_admin(adm);
  perform pg_temp.como(a);
  l := public.inbox_list();
  perform pg_temp.yo();
  assert (l -> 'admin') = '{"es_admin": false}'::jsonb, 'not an admin, said so';
  perform pg_temp.como(adm);
  l := public.inbox_list();
  perform pg_temp.yo();
  assert (l -> 'admin' ->> 'es_admin')::boolean and l -> 'admin' ? 'labs_pending', 'an admin, with counts';
end $$;
