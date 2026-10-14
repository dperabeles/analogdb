-- Supabase default table privileges can grant authenticated ALL directly.
-- Reset that inherited grant, then allow only the operations used by the app.
-- RLS owner-only policies remain in force for every allowed row operation.
revoke all on public.profile_preferences, public.annual_film_goals from authenticated;
grant select, insert, update on public.profile_preferences to authenticated;
grant select, insert, update, delete on public.annual_film_goals to authenticated;
