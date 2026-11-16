-- Luckyfilm C400 (sold as Lucky Color 400): ISO 400 daylight color negative,
-- C-41, released in 2026 after C200. Named like the catalog's other Lucky
-- films (Luckyfilm · C200, SHD 100, SHD 400). A pending private suggestion
-- of the same film by another account is left for the admin to merge.
insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
values ('Luckyfilm', 'C400', 400, 'COLOR', true, 'approved')
on conflict do nothing;
