-- Review of 20-nov (Diego: «hagamos bien las cosas»): how cameras meet the
-- catalogue, end to end.
--
-- 1. The record of each link goes with its camera: deleting a camera, or the
--    account that owns it, deletes how it was written. Before, it outlived
--    both.
-- 2. A camera written all in the maker field («Leica M6», no model) is read
--    as maker + model when it starts with a catalogue maker.
-- 3. The panel groups what was written by key, not by exact text:
--    «canon ae-1» and «Canon AE-1 » are one card, and linking or putting
--    away a card takes all of them.
-- 4. A camera saved by hand that is exactly a catalogue model, by key, links
--    itself on saving (as the 22 did on 20-nov). One per model per person
--    until January still holds; undoing a link never links it again.

-- ── 1 ─────────────────────────────────────────────────────────────────────
delete from app_private.camera_matches m
 where not exists (select 1 from public.cameras c where c.id = m.camera_id);
alter table app_private.camera_matches
  add constraint camera_matches_camera_id_fkey
  foreign key (camera_id) references public.cameras(id) on delete cascade
  -- Checked at commit: a camera saved by hand is recorded by its BEFORE
  -- trigger, before its row exists. The cascade still acts at once.
  deferrable initially deferred;
create index camera_matches_camera_idx on app_private.camera_matches (camera_id);

-- ── 2 ─────────────────────────────────────────────────────────────────────
-- What was written, as maker and model: with no model and a maker field that
-- starts with a catalogue maker and a space, the rest is the model.
create function app_private.camera_text_split(p_maker text, p_model text, out maker text, out model text)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_name text;
begin
  maker := p_maker;
  model := p_model;
  if nullif(btrim(coalesce(p_model, '')), '') is not null or p_maker is null then
    return;
  end if;
  select mf.name into v_name
    from public.manufacturers mf
   where mf.status = 'approved'
     and exists (select 1 from public.camera_models m
                  where m.manufacturer_id = mf.id and m.status = 'approved')
     and lower(left(btrim(p_maker), length(mf.name) + 1)) = lower(mf.name) || ' '
   order by length(mf.name) desc
   limit 1;
  if v_name is not null then
    maker := v_name;
    model := btrim(substr(btrim(p_maker), length(v_name) + 2));
  end if;
end;
$$;

-- One key for what was written: the panel groups and links by it.
create function app_private.camera_text_key(p_maker text, p_model text)
returns text
language sql
stable
set search_path = ''
as $$
  select app_private.manufacturer_key(s.maker) || '|' || app_private.camera_model_key(s.model)
    from app_private.camera_text_split(p_maker, p_model) s
$$;

create or replace function app_private.camera_text_model(p_maker text, p_model text)
returns bigint
language sql
stable
set search_path = ''
as $$
  select m.id
    from app_private.camera_text_split(p_maker, p_model) s
    join public.manufacturers mf on app_private.manufacturer_key(mf.name) = app_private.manufacturer_key(s.maker)
    join public.camera_models m on m.manufacturer_id = mf.id
   where m.status = 'approved'
     and app_private.camera_model_key(m.name) in (
           app_private.camera_model_key(s.model),
           app_private.camera_model_key(
             case when lower(left(btrim(s.model), length(btrim(s.maker)) + 1)) = lower(btrim(s.maker)) || ' '
                  then substr(btrim(s.model), length(btrim(s.maker)) + 2)
                  else s.model end))
   order by m.id
   limit 1
$$;

create or replace function app_private.camera_text_suggestion(p_maker text, p_model text)
returns bigint
language sql
stable
set search_path = ''
as $$
  with s as (select * from app_private.camera_text_split(p_maker, p_model)),
  typed as (
    -- The model as written, without the maker in front («Mamiya 645J» → «645J»).
    select s.maker,
           app_private.camera_model_key(
             case when lower(left(btrim(s.model), length(btrim(s.maker)) + 1)) = lower(btrim(s.maker)) || ' '
                  then substr(btrim(s.model), length(btrim(s.maker)) + 2)
                  else s.model end) k
      from s
  )
  select coalesce(
    app_private.camera_text_model(p_maker, p_model),
    (select m.id
       from public.camera_models m
       join public.manufacturers mf on mf.id = m.manufacturer_id
       cross join typed t
      where m.status = 'approved'
        and app_private.manufacturer_key(mf.name) = app_private.manufacturer_key(t.maker)
        -- A key of one or two characters («6») is inside too many others.
        and least(length(app_private.camera_model_key(m.name)), length(t.k)) >= 3
        and (strpos(t.k, app_private.camera_model_key(m.name)) > 0
             or strpos(app_private.camera_model_key(m.name), t.k) > 0)
      order by abs(length(app_private.camera_model_key(m.name)) - length(t.k)), m.id
      limit 1))
$$;

-- ── 3 ─────────────────────────────────────────────────────────────────────
create or replace function public.admin_unmatched_cameras()
returns table (maker text, model text, cameras bigint, people bigint, suggestion_id bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.require_admin();
  return query
    with g as (
      select app_private.camera_text_key(c.maker, c.model) k,
             min(c.maker) maker, min(c.model) model,
             count(*) cameras, count(distinct c.owner_user_id) people
        from public.cameras c
       where c.camera_model_id is null
         and not exists (select 1 from app_private.camera_match_hidden h where h.camera_id = c.id)
       group by 1
    )
    select g.maker, g.model, g.cameras, g.people,
           app_private.camera_text_suggestion(g.maker, g.model)
      from g
     order by lower(coalesce(g.maker, '')), lower(coalesce(g.model, ''));
end;
$$;

create or replace function public.admin_match_cameras(p_maker text, p_model text, p_model_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_batch uuid := gen_random_uuid();
  v_key text := app_private.camera_text_key(p_maker, p_model);
  v_ids bigint[];
  v_n integer;
begin
  if not exists (select 1 from public.camera_models where id = p_model_id and status = 'approved') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select array_agg(c.id order by c.id) into v_ids
    from public.cameras c
   where c.camera_model_id is null
     and app_private.camera_text_key(c.maker, c.model) = v_key
     and not exists (select 1 from app_private.camera_match_hidden h where h.camera_id = c.id);
  if v_ids is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  v_n := app_private.match_cameras(v_ids, p_model_id, v_batch, v_admin);
  if v_n > 0 then
    insert into app_private.camera_match_hidden (camera_id, batch, hidden_by)
    select c.id, v_batch, v_admin
      from public.cameras c
     where c.id = any (v_ids) and c.camera_model_id is null
    on conflict (camera_id) do nothing;
  end if;
  return jsonb_build_object('batch', v_batch, 'matched', v_n,
                            'skipped', cardinality(v_ids) - v_n);
end;
$$;

create or replace function public.admin_hide_unmatched(p_maker text, p_model text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_batch uuid := gen_random_uuid();
  v_key text := app_private.camera_text_key(p_maker, p_model);
  v_n integer;
begin
  insert into app_private.camera_match_hidden (camera_id, batch, hidden_by)
  select c.id, v_batch, v_admin
    from public.cameras c
   where c.camera_model_id is null
     and app_private.camera_text_key(c.maker, c.model) = v_key
  on conflict (camera_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  return jsonb_build_object('batch', v_batch, 'hidden', v_n);
end;
$$;

-- ── 4 ─────────────────────────────────────────────────────────────────────
-- Before cameras_aa_follow_model (triggers run by name): a camera saved by
-- hand that is exactly a catalogue model takes it, and that trigger then
-- writes the model's name and data. Recorded like every link.
create function app_private.cameras_link_by_key()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_model bigint;
begin
  if new.camera_model_id is not null
     or coalesce(current_setting('app.camera_keep_text', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.maker is not distinct from old.maker
     and new.model is not distinct from old.model then
    return new;
  end if;
  v_model := app_private.camera_text_model(new.maker, new.model);
  if v_model is null then
    return new;
  end if;
  -- One per model per person (until January), and never the very name of
  -- another of the person's cameras.
  if exists (
    select 1 from public.cameras o
      join public.camera_models m on m.id = v_model
      join public.manufacturers mf on mf.id = m.manufacturer_id
     where o.owner_user_id = new.owner_user_id
       and o.id is distinct from new.id
       and (o.camera_model_id = v_model or (o.maker = mf.name and o.model = m.name))
  ) then
    return new;
  end if;
  insert into app_private.camera_matches (batch, camera_id, owner_user_id, model_id, before, matched_by)
  values (gen_random_uuid(), new.id, new.owner_user_id, v_model,
          jsonb_build_object(
            'maker', new.maker, 'model', new.model, 'type', new.type, 'format', new.format,
            'mount', new.mount, 'frame_size', new.frame_size,
            'supports_interchangeable_lenses', new.supports_interchangeable_lenses),
          null);
  new.camera_model_id := v_model;
  return new;
end;
$$;
create trigger cameras_a_link_by_key
before insert or update on public.cameras
for each row execute function app_private.cameras_link_by_key();

-- Undoing a link keeps the text as it was: it does not link again.
create or replace function public.admin_camera_match_undo(p_batch uuid)
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
  perform set_config('app.camera_keep_text', 'on', true);
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
  delete from app_private.camera_match_hidden where batch = p_batch;
  perform set_config('app.camera_keep_text', '', true);
  return v_n;
end;
$$;

revoke all on function app_private.camera_text_split(text, text) from public, anon, authenticated;
revoke all on function app_private.camera_text_key(text, text) from public, anon, authenticated;
revoke all on function app_private.cameras_link_by_key() from public, anon, authenticated;
