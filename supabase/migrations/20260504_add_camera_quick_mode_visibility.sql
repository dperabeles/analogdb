alter table public.cameras
  add column if not exists show_in_quick_mode boolean not null default true;

update public.cameras
set show_in_quick_mode = true
where show_in_quick_mode is null;

comment on column public.cameras.show_in_quick_mode is
  'Controls whether the camera appears in quick roll creation flows. Historical cameras stay in the catalog when false.';
