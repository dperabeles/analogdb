-- The cameras people already had meet the catalogue (Diego, 20-nov): «como
-- en labs», each one ends with the correct name of its model.
--
-- - The ones whose maker and model are the same as a catalogue model, by key,
--   are linked here; the camera then follows its model (name, type, format,
--   mount) like any camera chosen from the catalogue.
-- - The rest the admin links from the panel, grouped by what was written and
--   never by whose it is.
-- - One camera per model per person (until January): a camera that would be
--   the person's second of a model stays as it is.
-- - What each camera was before is kept, so every link can be undone.

create table app_private.camera_matches (
  id bigint generated always as identity primary key,
  batch uuid not null,
  camera_id bigint not null,
  owner_user_id uuid not null,
  model_id bigint not null,
  before jsonb not null,
  matched_by uuid,
  matched_at timestamptz not null default now(),
  undone_at timestamptz
);
create index camera_matches_batch_idx on app_private.camera_matches (batch);
revoke all on app_private.camera_matches from public, anon, authenticated;

-- The approved model a written maker and model are, by key; the model may
-- carry the maker in front («Canon AE-1» under Canon). Null when none is.
create function app_private.camera_text_model(p_maker text, p_model text)
returns bigint
language sql
stable
set search_path = ''
as $$
  select m.id
    from public.camera_models m
    join public.manufacturers mf on mf.id = m.manufacturer_id
   where m.status = 'approved'
     and app_private.manufacturer_key(mf.name) = app_private.manufacturer_key(p_maker)
     and app_private.camera_model_key(m.name) in (
           app_private.camera_model_key(p_model),
           app_private.camera_model_key(
             case when lower(left(btrim(p_model), length(btrim(p_maker)) + 1)) = lower(btrim(p_maker)) || ' '
                  then substr(btrim(p_model), length(btrim(p_maker)) + 2)
                  else p_model end))
   order by m.id
   limit 1
$$;

-- The closest approved model of the same maker, for the panel to offer
-- first: the same one by key, or else one whose key holds the other.
create function app_private.camera_text_suggestion(p_maker text, p_model text)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce(
    app_private.camera_text_model(p_maker, p_model),
    (select m.id
       from public.camera_models m
       join public.manufacturers mf on mf.id = m.manufacturer_id
      where m.status = 'approved'
        and app_private.manufacturer_key(mf.name) = app_private.manufacturer_key(p_maker)
        and length(app_private.camera_model_key(m.name)) > 0
        and length(app_private.camera_model_key(p_model)) > 0
        and (strpos(app_private.camera_model_key(p_model), app_private.camera_model_key(m.name)) > 0
             or strpos(app_private.camera_model_key(m.name), app_private.camera_model_key(p_model)) > 0)
      order by abs(length(app_private.camera_model_key(m.name)) - length(app_private.camera_model_key(p_model))), m.id
      limit 1))
$$;

-- Links these cameras, still without a model, to this model and keeps what
-- each one was. A person's second camera of the model is left as it is.
create function app_private.match_cameras(p_ids bigint[], p_model bigint, p_batch uuid, p_by uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.cameras;
  v_n integer := 0;
begin
  for r in
    select c.* from public.cameras c
     where c.id = any (p_ids) and c.camera_model_id is null
     order by c.id
     for update
  loop
    continue when exists (
      select 1 from public.cameras o
       where o.owner_user_id = r.owner_user_id and o.camera_model_id = p_model);
    begin
      update public.cameras set camera_model_id = p_model where id = r.id;
    exception when unique_violation then
      continue;
    end;
    insert into app_private.camera_matches (batch, camera_id, owner_user_id, model_id, before, matched_by)
    values (p_batch, r.id, r.owner_user_id, p_model,
            jsonb_build_object(
              'maker', r.maker, 'model', r.model, 'type', r.type, 'format', r.format,
              'mount', r.mount, 'frame_size', r.frame_size,
              'supports_interchangeable_lenses', r.supports_interchangeable_lenses),
            p_by);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Every camera without a model whose text is a catalogue model, by key.
create function app_private.match_cameras_by_key()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch uuid := gen_random_uuid();
  v_n integer := 0;
  r record;
begin
  for r in
    select s.mid, array_agg(s.id order by s.id) ids
      from (select c.id, app_private.camera_text_model(c.maker, c.model) mid
              from public.cameras c where c.camera_model_id is null) s
     where s.mid is not null
     group by s.mid
  loop
    v_n := v_n + app_private.match_cameras(r.ids, r.mid, v_batch, null);
  end loop;
  return v_n;
end;
$$;

-- ── Panel ─────────────────────────────────────────────────────────────────

-- The cameras still without a model, grouped by what was written: how many
-- and of how many people, never whose. With the closest model to offer.
create function public.admin_unmatched_cameras()
returns table (maker text, model text, cameras bigint, people bigint, suggestion_id bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.require_admin();
  return query
    select c.maker, c.model, count(*), count(distinct c.owner_user_id),
           app_private.camera_text_suggestion(c.maker, c.model)
      from public.cameras c
     where c.camera_model_id is null
     group by c.maker, c.model
     order by lower(coalesce(c.maker, '')), lower(coalesce(c.model, ''));
end;
$$;

-- Links every camera written exactly so to an approved model.
create function public.admin_match_cameras(p_maker text, p_model text, p_model_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_batch uuid := gen_random_uuid();
  v_ids bigint[];
  v_n integer;
begin
  if not exists (select 1 from public.camera_models where id = p_model_id and status = 'approved') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select array_agg(c.id order by c.id) into v_ids
    from public.cameras c
   where c.camera_model_id is null
     and c.maker is not distinct from p_maker
     and c.model is not distinct from p_model;
  if v_ids is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  v_n := app_private.match_cameras(v_ids, p_model_id, v_batch, v_admin);
  return jsonb_build_object('batch', v_batch, 'matched', v_n,
                            'skipped', cardinality(v_ids) - v_n);
end;
$$;

-- Puts back what the cameras of a link were, without a model.
create function public.admin_camera_match_undo(p_batch uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  r app_private.camera_matches;
  v_n integer := 0;
begin
  for r in
    select * from app_private.camera_matches
     where batch = p_batch and undone_at is null
     order by id
     for update
  loop
    update public.cameras
       set camera_model_id = null,
           maker = r.before ->> 'maker',
           model = r.before ->> 'model',
           type = r.before ->> 'type',
           format = r.before ->> 'format',
           mount = r.before ->> 'mount',
           frame_size = r.before ->> 'frame_size',
           supports_interchangeable_lenses = (r.before ->> 'supports_interchangeable_lenses')::boolean
     where id = r.camera_id and camera_model_id = r.model_id;
    if found then
      v_n := v_n + 1;
    end if;
    update app_private.camera_matches set undone_at = now() where id = r.id;
  end loop;
  return v_n;
end;
$$;

revoke all on function app_private.camera_text_model(text, text) from public, anon, authenticated;
revoke all on function app_private.camera_text_suggestion(text, text) from public, anon, authenticated;
revoke all on function app_private.match_cameras(bigint[], bigint, uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.match_cameras_by_key() from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.admin_unmatched_cameras()',
    'public.admin_match_cameras(text, text, bigint)',
    'public.admin_camera_match_undo(uuid)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- The ones that are a catalogue model by key, now.
select app_private.match_cameras_by_key();
