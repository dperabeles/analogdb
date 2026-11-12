-- ANA-135: the frame size of a 120 camera is data about the camera, not a
-- format. Some cameras were saved with "6x4.5" (or 6x6, 6x7, 6x9) as their
-- format, so nothing that matches on 120 found them. The format is 120 and
-- the size lives beside it; nothing depends on it.

alter table public.cameras add column frame_size text;

alter table public.cameras add constraint cameras_frame_size_valid
  check (frame_size is null or frame_size in ('6x4.5', '6x6', '6x7', '6x9'));

comment on column public.cameras.frame_size is
  'Frame size of a 120 camera (6x4.5, 6x6, 6x7, 6x9). Informative only; '
  'null for any other format.';

-- Only a 120 camera has one: changing the format away from 120 drops it
-- instead of failing, so a client that does not know the column (an older
-- web or app) can still edit the camera. A size sent as the format (the
-- web's free-text camera format on a roll) is saved as 120 with that size.
create function app_private.cameras_frame_size_only_120()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.format in ('6x4.5', '6x6', '6x7', '6x9') then
    new.frame_size := new.format;
    new.format := '120';
  elsif new.format is distinct from '120' then
    new.frame_size := null;
  end if;
  return new;
end;
$$;

create trigger cameras_frame_size_only_120
  before insert or update on public.cameras
  for each row execute function app_private.cameras_frame_size_only_120();

-- Cameras saved with the size as their format become 120 with that size
-- (the trigger above does the move).
update public.cameras
   set format = format
 where format in ('6x4.5', '6x6', '6x7', '6x9');
