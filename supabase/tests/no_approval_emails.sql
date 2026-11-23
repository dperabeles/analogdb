-- Accounts are active from sign-up (profiles.status defaults to approved),
-- so nothing sends «pending sign-up» or «account approved» emails any more
-- (20261123120000). Suspension still goes through app_private.require_approved.
do $$
begin
  assert not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass
    and tgname in ('profiles_notify_pending_signup', 'profiles_notify_approved')), 'approval email triggers are gone';
  assert to_regprocedure('public.notify_pending_signup()') is null, 'notify_pending_signup is gone';
  assert to_regprocedure('public.notify_profile_approved()') is null, 'notify_profile_approved is gone';
  assert to_regprocedure('app_private.require_approved()') is not null
      or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'app_private' and p.proname = 'require_approved'),
    'the suspension gate stays';
  assert (select column_default from information_schema.columns where table_schema = 'public'
            and table_name = 'profiles' and column_name = 'status') = '''approved''::text', 'accounts start active';
  raise notice 'no_approval_emails: all checks passed';
end $$;
