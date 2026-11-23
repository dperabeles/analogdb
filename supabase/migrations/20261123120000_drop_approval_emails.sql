-- No more manual approval (Diego, 23-nov-2026): accounts are active from
-- sign-up (profiles.status defaults to 'approved' since ANA-81), so the
-- «pending sign-up» and «account approved» emails can no longer happen.
-- Their triggers and functions go. Suspension stays: a suspended account is
-- status 'rejected' and app_private.require_approved still keeps it out.
-- The edge functions they called are left deployed and unused for now.
drop trigger if exists profiles_notify_pending_signup on public.profiles;
drop trigger if exists profiles_notify_approved on public.profiles;
drop function if exists public.notify_pending_signup();
drop function if exists public.notify_profile_approved();
