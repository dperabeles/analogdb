-- An optional serial number for a camera or a lens (Diego, 20-nov). It is
-- new data: the privacy policy says so from 20-nov and the in-app notice
-- went out that day, so it takes effect on 25-nov. The app shows the field
-- from that day; older apps never send it.
alter table public.cameras
  add column serial_number text
  constraint cameras_serial_number_check
    check (serial_number is null or char_length(btrim(serial_number)) between 1 and 64);

alter table public.lenses
  add column serial_number text
  constraint lenses_serial_number_check
    check (serial_number is null or char_length(btrim(serial_number)) between 1 and 64);

comment on column public.cameras.serial_number is
  'Optional serial number the owner types; only the owner sees it (RLS). From 2026-11-25.';
comment on column public.lenses.serial_number is
  'Optional serial number the owner types; only the owner sees it (RLS). From 2026-11-25.';
