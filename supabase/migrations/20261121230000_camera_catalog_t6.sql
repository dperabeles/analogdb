-- Catálogo de cámaras, Tanda 6 (Diego, 20-nov: «Aprobado»): los modelos que
-- las cámaras ya escritas pedían y el catálogo no tenía.
--
-- · Pentax Super Program: el nombre norteamericano de la Super A, su propio
--   modelo (la regla de los nombres regionales), con su año oficial.
-- · El año solo donde la ficha oficial o varias fuentes coinciden.
-- Después, las cámaras que ya los pedían quedan ligadas: por clave las que se
-- escribieron igual, y por su texto exacto las que Diego aprobó en el chat
-- (también la Leica M6 y la Mamiya 645J que se quitaron de la lista; si su
-- dueño ya tiene ese modelo siguen quitadas hasta enero). La sugerencia del panel deja de contar claves muy
-- cortas («6» dentro de «645J» sugería la Mamiya 6).

insert into public.camera_models
  (manufacturer_id, name, type, format, frame_sizes, mount_id, interchangeable, year_from,
   source, source_ref, status)
select app_private.manufacturer_for(v.maker, null, true), v.name, v.type, v.format, v.frames,
       (select m.id from public.lens_mounts m where m.status = 'approved' and m.name = v.mount),
       v.interchangeable, v.year, v.source, v.ref, 'approved'
from (values
  ('Pentax', 'Super Program', 'SLR', '35mm', '{}'::text[], 'Pentax K', true, 1983::integer, 'curada', 'https://en.wikipedia.org/wiki/Pentax_Super-A'),
  ('Pentax', 'PC-330', 'P&S', '35mm', '{}'::text[], 'Lente integrado', false, null::integer, 'curada', null),
  ('Pentax', 'IQZoom 115M', 'P&S', '35mm', '{}'::text[], 'Lente integrado', false, null::integer, 'curada', null),
  ('Yashica', 'FX-2', 'SLR', '35mm', '{}'::text[], 'Contax/Yashica', true, 1976::integer, 'curada', 'https://cameracollector.net/yashica-fx-2/'),
  ('Yashica', 'EZS Zoom 105', 'P&S', '35mm', '{}'::text[], 'Lente integrado', false, null::integer, 'curada', null),
  ('Minox', '35 GL', 'P&S', '35mm', '{}'::text[], 'Lente integrado', false, 1979::integer, 'curada', 'https://www.mshobbies.co.uk/minox-35mm-cameras.shtml'),
  ('Fujica', 'V2', 'Rangefinder', '35mm', '{}'::text[], 'Lente integrado', false, null::integer, 'curada', null)
) v(maker, name, type, format, frames, mount, interchangeable, year, source, ref)
on conflict do nothing;

create or replace function app_private.camera_text_suggestion(p_maker text, p_model text)
returns bigint
language sql
stable
set search_path = ''
as $$
  with typed as (
    -- The model as written, without the maker in front («Mamiya 645J» → «645J»).
    select app_private.camera_model_key(
             case when lower(left(btrim(p_model), length(btrim(p_maker)) + 1)) = lower(btrim(p_maker)) || ' '
                  then substr(btrim(p_model), length(btrim(p_maker)) + 2)
                  else p_model end) k
  )
  select coalesce(
    app_private.camera_text_model(p_maker, p_model),
    (select m.id
       from public.camera_models m
       join public.manufacturers mf on mf.id = m.manufacturer_id
       cross join typed t
      where m.status = 'approved'
        and app_private.manufacturer_key(mf.name) = app_private.manufacturer_key(p_maker)
        -- A key of one or two characters («6») is inside too many others.
        and least(length(app_private.camera_model_key(m.name)), length(t.k)) >= 3
        and (strpos(t.k, app_private.camera_model_key(m.name)) > 0
             or strpos(app_private.camera_model_key(m.name), t.k) > 0)
      order by abs(length(app_private.camera_model_key(m.name)) - length(t.k)), m.id
      limit 1))
$$;

-- The ones written as the model, by key.
select app_private.match_cameras_by_key();

-- The ones Diego named, by their exact text; the two put away come back.
do $$
declare
  v_batch uuid := gen_random_uuid();
  r record;
  v_ids bigint[];
  v_model bigint;
begin
  for r in
    select * from (values
      ('Fujifilm', 'Fujica V2', 'Fujica', 'V2'),
      ('Yashica', 'ESZ105 Zoom', 'Yashica', 'EZS Zoom 105'),
      ('Leica M6', null, 'Leica', 'M6'),
      ('Mamiya', 'Mamiya 645J', 'Mamiya', 'M645 J')
    ) t(maker, model, into_maker, into_name)
  loop
    select m.id into v_model
      from public.camera_models m join public.manufacturers mf on mf.id = m.manufacturer_id
     where m.status = 'approved'
       and app_private.manufacturer_key(mf.name) = app_private.manufacturer_key(r.into_maker)
       and app_private.camera_model_key(m.name) = app_private.camera_model_key(r.into_name);
    select array_agg(c.id order by c.id) into v_ids
      from public.cameras c
     where c.camera_model_id is null
       and c.maker is not distinct from r.maker
       and c.model is not distinct from r.model;
    continue when v_model is null or v_ids is null;
    perform app_private.match_cameras(v_ids, v_model, v_batch, null);
    -- One that was put away comes back only if it was linked; a second of a
    -- model its owner already has stays put away until January.
    delete from app_private.camera_match_hidden h
     using public.cameras c
     where h.camera_id = c.id and c.id = any (v_ids) and c.camera_model_id is not null;
  end loop;
end $$;
