-- Kodak Verita 200D (5206 in 35mm, 7206 in 16mm): daylight color negative
-- motion picture film, ISO 200, process ECN-2, no remjet. Kodak released it
-- in April 2026; it is not sold for still cameras, but labs respool it, and
-- Diego shoots it from such loads. Same shape as the Vision3 entries.
insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
values ('Kodak', 'Verita 200D', 200, 'COLOR', true, 'approved')
on conflict do nothing;
