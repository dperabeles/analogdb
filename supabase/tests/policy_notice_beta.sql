-- During the TestFlight beta a policy notice may take effect the day it is
-- published (20261121220000). Run after inbox_helpers.sql, inside BEGIN /
-- ROLLBACK. Synthetic accounts only.
do $$
declare
  a uuid := pg_temp.buzon_user('beta_a');
  adm uuid := pg_temp.buzon_user('beta_adm');
  today date := (now() at time zone 'America/Mexico_City')::date;
  pol uuid;
begin
  update public.profiles set created_at = now() - interval '1 day' where user_id in (a, adm);
  perform pg_temp.buzon_admin(adm);
  assert app_private.policy_notice_min_days() = 0, 'no wait during the beta';

  perform pg_temp.como(adm);
  perform pg_temp.espera_error(format(
    'select public.inbox_publish_policy(%L, %L, %L, %L, %L, %L::date)',
    't', 't', 's', 's', 'https://analog-archive.com/privacy', today - 1), 'P1206');
  pol := public.inbox_publish_policy('t', 't', 's', 's', 'https://analog-archive.com/privacy', today);
  perform pg_temp.yo();
  assert exists (select 1 from public.inbox_notices where owner_user_id = a and policy_id = pol),
    'a notice that takes effect today reaches everyone';

  perform pg_temp.como(a);
  perform pg_temp.espera_error(format(
    'select public.inbox_publish_policy(%L, %L, %L, %L, %L, %L::date)',
    't', 't', 's', 's', 'https://analog-archive.com/privacy', today), 'P1205');
  perform pg_temp.yo();
end $$;
