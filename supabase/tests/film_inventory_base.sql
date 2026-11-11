-- Finance base, per-account access and command receipts (ANA-173).
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare a uuid; b uuid; p uuid; r uuid; cmd uuid := gen_random_uuid();
begin
  -- ISO 4217 catalog: official minor units, no metals, test codes or funds.
  assert (select minor_unit from public.currencies where code = 'MXN') = 2, 'MXN has 2 decimals';
  assert (select minor_unit from public.currencies where code = 'USD') = 2, 'USD has 2 decimals';
  assert (select minor_unit from public.currencies where code = 'EUR') = 2, 'EUR has 2 decimals';
  assert (select minor_unit from public.currencies where code = 'JPY') = 0, 'JPY has no decimals';
  assert (select minor_unit from public.currencies where code = 'CLP') = 0, 'CLP has no decimals';
  assert (select minor_unit from public.currencies where code = 'KWD') = 3, 'KWD has 3 decimals';
  assert (select minor_unit from public.currencies where code = 'BHD') = 3, 'BHD has 3 decimals';
  assert exists (select 1 from public.currencies where code = 'XOF'), 'CFA franc is a currency';
  assert not exists (select 1 from public.currencies
                     where code in ('XAU','XAG','XPT','XPD','XDR','XTS','XXX')), 'no metals or test codes';
  assert not exists (select 1 from public.currencies
                     where code in ('BOV','CHE','CHW','CLF','COU','MXV','USN','UYI','UYW')), 'no fund codes';

  a := pg_temp.inv_user('basea');
  b := pg_temp.inv_user('baseb');
  p := pg_temp.inv_user('basep', 'pending');
  r := pg_temp.inv_user('baser', 'rejected');
  perform pg_temp.inv_member(a);
  perform pg_temp.inv_member(p);
  perform pg_temp.inv_member(r);

  -- Access: approved member only, unless the feature is open to everyone.
  assert app_private.feature_enabled(a, 'film_inventory'), 'approved member is enabled';
  assert not app_private.feature_enabled(b, 'film_inventory'), 'approved non-member is not';
  assert not app_private.feature_enabled(p, 'film_inventory'), 'pending member is not';
  assert not app_private.feature_enabled(r, 'film_inventory'), 'rejected member is not';
  assert not app_private.feature_enabled(gen_random_uuid(), 'film_inventory'), 'unknown account is not';
  assert not app_private.feature_enabled(a, 'no_such_feature'), 'unknown feature is off';
  update app_private.feature_flags set enabled_for_everyone = true where feature = 'film_inventory';
  assert app_private.feature_enabled(b, 'film_inventory'), 'open feature reaches non-members';
  assert not app_private.feature_enabled(p, 'film_inventory'), 'open feature still needs approval (pending)';
  assert not app_private.feature_enabled(r, 'film_inventory'), 'open feature still needs approval (rejected)';
  update app_private.feature_flags set enabled_for_everyone = false where feature = 'film_inventory';

  -- Default currency: one row per account, only for enabled accounts.
  perform pg_temp.como(a);
  assert public.my_features() = array['film_inventory'], 'member sees its feature';
  perform public.set_default_currency('USD');
  perform public.set_default_currency('MXN');
  perform pg_temp.espera_error($q$select public.set_default_currency('ZZZ')$q$, 'P1103');
  assert (select count(*) from public.finance_preferences) = 1, 'member reads its preference';
  perform pg_temp.yo();
  assert (select count(*) from public.finance_preferences where user_id = a) = 1, 'single preference row';
  assert (select default_currency from public.finance_preferences where user_id = a) = 'MXN', 'last choice wins';

  perform pg_temp.como(b);
  assert public.my_features() = '{}'::text[], 'non-member sees no features';
  perform pg_temp.espera_error($q$select public.set_default_currency('MXN')$q$, 'P1102');
  assert (select count(*) from public.finance_preferences) = 0, 'other preferences are hidden';
  perform pg_temp.yo();

  perform pg_temp.como(p);
  perform pg_temp.espera_error($q$select public.set_default_currency('MXN')$q$, 'P1102');
  perform pg_temp.yo();

  -- A request without a subject is not a session.
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  execute 'set local role authenticated';
  assert public.my_features() = '{}'::text[], 'no session, no features';
  perform pg_temp.espera_error($q$select public.set_default_currency('MXN')$q$, 'P1101');
  perform pg_temp.yo();

  perform pg_temp.como(null);
  perform pg_temp.espera_error($q$select public.my_features()$q$, '42501');
  perform pg_temp.espera_error($q$select public.set_default_currency('MXN')$q$, '42501');
  perform pg_temp.yo();

  -- Receipts: same command and request replays; anything else conflicts.
  assert app_private.command_replay(a, cmd, 'k', '{"x":1}') is null, 'new command has no receipt';
  assert app_private.command_record(a, cmd, 'k', '{"x":1}', '{"ok":true}') = '{"ok":true}', 'record returns result';
  assert app_private.command_replay(a, cmd, 'k', '{"x":1}') = '{"ok":true}', 'same request replays';
  perform pg_temp.espera_error(format('select app_private.command_replay(%L, %L, %L, %L)',
    a, cmd, 'k', '{"x":2}'), 'P1106');
  perform pg_temp.espera_error(format('select app_private.command_replay(%L, %L, %L, %L)',
    a, cmd, 'other', '{"x":1}'), 'P1106');
  perform pg_temp.espera_error(format('select app_private.command_replay(%L, %L, %L, %L)',
    b, cmd, 'k', '{"x":1}'), 'P1106');
  perform pg_temp.espera_error(format('select app_private.command_replay(%L, null, %L, %L)',
    a, 'k', '{"x":1}'), 'P1103');

  perform pg_temp.como(a);
  assert (select count(*) from public.inventory_commands) = 1, 'owner reads its receipt';
  perform pg_temp.yo();
  perform pg_temp.como(b);
  assert (select count(*) from public.inventory_commands) = 0, 'other receipts are hidden';
  perform pg_temp.yo();

  -- Nobody writes these tables directly from the app.
  assert has_table_privilege('authenticated', 'public.currencies', 'SELECT'), 'catalog readable';
  assert not has_table_privilege('authenticated', 'public.currencies', 'INSERT'), 'catalog not writable';
  assert not has_table_privilege('authenticated', 'public.finance_preferences', 'INSERT'), 'preference only via function';
  assert not has_table_privilege('authenticated', 'public.inventory_commands', 'INSERT'), 'receipts only via functions';
  assert not has_table_privilege('anon', 'public.finance_preferences', 'SELECT'), 'anon reads nothing';
  assert not has_function_privilege('anon', 'public.my_features()', 'EXECUTE'), 'anon cannot call';
  assert not has_function_privilege('authenticated', 'app_private.feature_enabled(uuid,text)', 'EXECUTE'), 'private check not callable';
  assert not has_table_privilege('authenticated', 'app_private.feature_members', 'SELECT'), 'members list private';
end $$;
