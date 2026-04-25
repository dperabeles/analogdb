begin;

drop policy if exists profiles_self_insert on public.profiles;
create policy profiles_self_insert
on public.profiles
for insert
to public
with check (
  user_id = auth.uid()
  and email = auth.jwt() ->> 'email'
  and status = 'pending'
  and approved_at is null
  and approved_by is null
  and rejected_at is null
  and rejected_by is null
);

drop policy if exists shared_film_stocks_update on public.film_stocks;
create policy shared_film_stocks_update
on public.film_stocks
for update
to public
using (public.app_is_admin(auth.uid()))
with check (public.app_is_admin(auth.uid()));

drop policy if exists shared_labs_update on public.labs;
create policy shared_labs_update
on public.labs
for update
to public
using (public.app_is_admin(auth.uid()))
with check (public.app_is_admin(auth.uid()));

revoke all on public.frame_tags from anon, authenticated;
alter table public.frame_tags enable row level security;

commit;
