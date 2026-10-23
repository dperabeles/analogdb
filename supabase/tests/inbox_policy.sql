-- Inbox policy notices: publishing and showing the legal change notice.
create function pg_temp.publish(p_days int, p_url text default 'https://analog-archive.com/privacy',
                                p_title text default 'Cambios en la privacidad')
returns uuid language sql as $$
  select public.inbox_publish_policy(p_title, 'Privacy changes', 'Resumen', 'Summary', p_url,
                                     (now() at time zone 'America/Mexico_City')::date + p_days);
$$;

do $$
declare
  a uuid := pg_temp.buzon_user('pol_a');
  a2 uuid := pg_temp.buzon_user('pol_a2');
  adm uuid := pg_temp.buzon_user('pol_adm');
  late uuid := pg_temp.buzon_user('pol_late');
  pol uuid; pol2 uuid; nid uuid; l jsonb; e jsonb; opened timestamptz;
begin
  -- Accounts that existed before publishing; "late" signs up at the same moment.
  update public.profiles set created_at = now() - interval '1 day' where user_id in (a, a2, adm);
  update public.profiles set notification_prefs = notification_prefs || '{"legal_updates": false}' where user_id = a2;
  perform pg_temp.buzon_admin(adm);

  perform pg_temp.como(a);
  perform pg_temp.espera_error('select pg_temp.publish(5)', 'P1205');
  perform pg_temp.como(adm);
  perform pg_temp.espera_error('select pg_temp.publish(4)', 'P1206');
  perform pg_temp.espera_error($q$select pg_temp.publish(5, 'http://analog-archive.com/privacy')$q$, 'P1203');
  perform pg_temp.espera_error($q$select pg_temp.publish(5, 'https://analog-archive.com/privacy', ' ')$q$, 'P1203');
  pol := pg_temp.publish(5);
  perform pg_temp.yo();
  assert pol is not null, 'published at 5 days';

  assert exists (select 1 from public.inbox_notices where owner_user_id = a and policy_id = pol), 'earlier account gets it';
  assert exists (select 1 from public.inbox_notices where owner_user_id = a2 and policy_id = pol), 'legal_updates off still gets it';
  assert not exists (select 1 from public.inbox_notices where owner_user_id = late and policy_id = pol), 'new account does not';

  -- First in the list and pinned until opened, even with newer notices.
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at)
  values (a, 'missing_lab', pg_temp.buzon_roll(a, 'Developed'), now(), now(), now() + interval '1 hour');
  perform pg_temp.como(a);
  l := public.inbox_list();
  e := (l -> 'notices') -> 0;
  assert e ->> 'kind' = 'policy_change' and (e ->> 'pinned')::boolean, 'policy first and pinned';
  assert e -> 'policy' ->> 'url' = 'https://analog-archive.com/privacy', 'policy content in the notice';
  nid := (e ->> 'id')::uuid;
  perform public.inbox_mark_all_read();
  e := (public.inbox_list() -> 'notices') -> 0;
  assert (e ->> 'read')::boolean and (e ->> 'pinned')::boolean, 'read but still pinned';
  assert public.inbox_mark(array[nid], true) = 1, 'opening counts';
  perform pg_temp.yo();
  select first_opened_at into opened from public.inbox_notices where id = nid;
  assert opened is not null, 'first opening recorded';
  perform pg_temp.como(a);
  assert not ((select x from jsonb_array_elements(public.inbox_list() -> 'notices') x
               where x ->> 'id' = nid::text) ->> 'pinned')::boolean, 'not pinned after opening';
  perform public.inbox_mark(array[nid], true);
  perform pg_temp.yo();
  assert (select first_opened_at from public.inbox_notices where id = nid) = opened, 'first opening never moves';

  -- Correcting a policy means publishing another.
  perform pg_temp.como(adm);
  pol2 := pg_temp.publish(5);
  perform pg_temp.yo();
  assert pol2 <> pol and (select count(*) from public.inbox_notices where owner_user_id = a and kind = 'policy_change') = 2,
         'two policies, two notices';
end $$;
