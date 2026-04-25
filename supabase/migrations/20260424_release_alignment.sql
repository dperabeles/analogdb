begin;

grant usage on schema public to anon, authenticated, service_role;

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

grant usage, select on all sequences in schema public to authenticated, service_role;

revoke all on table public.profiles from authenticated;
revoke all on table public.user_roles from authenticated;
revoke all on table public.film_stocks from authenticated;
revoke all on table public.labs from authenticated;
revoke all on table public.cameras from authenticated;
revoke all on table public.rolls from authenticated;
revoke all on table public.admin_actions from authenticated;
revoke all on table public.admin_action_approvals from authenticated;
revoke all on table public.rolls_flat from authenticated;

grant select, insert on table public.profiles to authenticated;
grant select, insert on table public.user_roles to authenticated;
grant select, insert, update on table public.film_stocks to authenticated;
grant select, insert, update on table public.labs to authenticated;
grant select, insert, update, delete on table public.cameras to authenticated;
grant select, insert, update, delete on table public.rolls to authenticated;
grant select on table public.admin_actions to authenticated;
grant select on table public.admin_action_approvals to authenticated;
grant select on table public.rolls_flat to authenticated;

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.film_stocks enable row level security;
alter table public.labs enable row level security;
alter table public.cameras enable row level security;
alter table public.rolls enable row level security;
alter table public.admin_actions enable row level security;
alter table public.admin_action_approvals enable row level security;

alter view public.rolls_flat set (security_invoker = true);

drop policy if exists shared_film_stocks_select on public.film_stocks;
create policy shared_film_stocks_select
on public.film_stocks
for select
to public
using (auth.role() = 'authenticated');

drop policy if exists shared_film_stocks_insert on public.film_stocks;
create policy shared_film_stocks_insert
on public.film_stocks
for insert
to public
with check (auth.role() = 'authenticated');

drop policy if exists shared_film_stocks_update on public.film_stocks;
create policy shared_film_stocks_update
on public.film_stocks
for update
to public
using (auth.role() = 'authenticated')
with check (auth.role() = 'authenticated');

drop policy if exists shared_labs_select on public.labs;
create policy shared_labs_select
on public.labs
for select
to public
using (auth.role() = 'authenticated');

drop policy if exists shared_labs_insert on public.labs;
create policy shared_labs_insert
on public.labs
for insert
to public
with check (auth.role() = 'authenticated');

drop policy if exists shared_labs_update on public.labs;
create policy shared_labs_update
on public.labs
for update
to public
using (auth.role() = 'authenticated')
with check (auth.role() = 'authenticated');

revoke all on function public.app_is_admin(uuid) from public;
revoke all on function public.app_is_founder(uuid) from public;
revoke all on function public.admin_set_profile_status(uuid, text) from public;
revoke all on function public.request_admin_action(text, uuid) from public;
revoke all on function public.cast_admin_action_vote(uuid, text) from public;
revoke all on function public.landing_metrics() from public;
revoke all on function public.app_is_admin(uuid) from anon;
revoke all on function public.app_is_founder(uuid) from anon;
revoke all on function public.admin_set_profile_status(uuid, text) from anon;
revoke all on function public.request_admin_action(text, uuid) from anon;
revoke all on function public.cast_admin_action_vote(uuid, text) from anon;
revoke all on function public.landing_metrics() from anon;
revoke all on function public.app_is_admin(uuid) from authenticated;
revoke all on function public.app_is_founder(uuid) from authenticated;
revoke all on function public.admin_set_profile_status(uuid, text) from authenticated;
revoke all on function public.request_admin_action(text, uuid) from authenticated;
revoke all on function public.cast_admin_action_vote(uuid, text) from authenticated;
revoke all on function public.landing_metrics() from authenticated;

grant execute on function public.app_is_admin(uuid) to authenticated;
grant execute on function public.app_is_founder(uuid) to authenticated;
grant execute on function public.admin_set_profile_status(uuid, text) to authenticated;
grant execute on function public.request_admin_action(text, uuid) to authenticated;
grant execute on function public.cast_admin_action_vote(uuid, text) to authenticated;
grant execute on function public.landing_metrics() to anon, authenticated;

commit;
