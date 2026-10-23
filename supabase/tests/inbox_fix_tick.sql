-- Review fix: an account that fails is recorded instead of hiding, and an odd
-- preference value does not break the inbox.
do $t$
declare
  ok uuid := pg_temp.buzon_user('ft_ok');
  bad uuid := pg_temp.buzon_user('ft_bad');
  odd uuid := pg_temp.buzon_user('ft_odd');
begin
  update public.profiles set notification_prefs = notification_prefs || '{"roll_reminders": ""}' where user_id = odd;
  assert app_private.inbox_reminders_on(odd), 'an empty string reads as on';
  perform pg_temp.como(odd);
  perform public.inbox_list();
  perform pg_temp.yo();
  update public.profiles set notification_prefs = notification_prefs || '{"roll_reminders": "false"}' where user_id = odd;
  assert not app_private.inbox_reminders_on(odd), 'the string false reads as off';

  insert into public.inbox_accounts (user_id, activated_at) values (ok, now() - interval '1 day'), (bad, now() - interval '1 day');
  execute format($f$create or replace function app_private.inbox_eval_gaps(p_uid uuid, p_now timestamptz)
    returns void language plpgsql as $b$ begin if p_uid = %L then raise exception 'poisoned'; end if; end $b$$f$, bad);
  perform app_private.inbox_tick('2026-11-02 15:00Z');
  assert (select last_evaluated_on from public.inbox_accounts where user_id = ok) is not null, 'the healthy account was evaluated';
  assert (select last_error from public.inbox_accounts where user_id = bad) like '%poisoned%', 'the failure is recorded';
  assert (select last_error_at from public.inbox_accounts where user_id = bad) = '2026-11-02 15:00Z', 'with its time';
  execute $f$create or replace function app_private.inbox_eval_gaps(p_uid uuid, p_now timestamptz)
    returns void language plpgsql as $b$ begin null; end $b$$f$;
  perform app_private.inbox_tick('2026-11-02 16:00Z');
  assert (select last_error from public.inbox_accounts where user_id = bad) is null, 'a later success clears it';
end $t$;
