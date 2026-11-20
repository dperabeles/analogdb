-- Instant formats leave the camera catalogue (Diego, 20-nov): Instax and
-- Polaroid cameras are not what people log in this app. Their models go, and
-- the vocabulary stops taking those formats and the instant type, so they
-- cannot come back as a proposal either.

-- Nobody's camera is instant or follows an instant model; if someone's were,
-- this stops before deleting anything.
do $$
begin
  if exists (
    select 1
      from public.cameras c
      left join public.camera_models m on m.id = c.camera_model_id
     where c.format ~ '^(Instax|Polaroid)' or c.type = 'Instantánea'
        or m.format ~ '^(Instax|Polaroid)' or m.type = 'Instantánea'
  ) then
    raise exception 'an instant camera is in someone''s equipment';
  end if;
end $$;

delete from public.camera_models
 where format ~ '^(Instax|Polaroid)' or type = 'Instantánea';

create or replace function app_private.camera_type_ok(p_type text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_type is null or p_type in (
    'SLR', 'Rangefinder', 'TLR', 'P&S', 'Folding', 'Vista / Gran formato',
    'Cine', 'Caja', 'Half-frame', 'Otro')
$$;

create or replace function app_private.camera_format_ok(p_format text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_format is null or p_format in (
    '35mm', '120', '220', '620', '127', '126', '110', 'APS', 'Super8', '16mm',
    'Large Format')
$$;
