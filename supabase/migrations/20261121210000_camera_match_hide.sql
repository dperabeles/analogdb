-- «Cámaras sin modelo» (Diego, 20-nov): after a link, its card goes, even
-- when some cameras stayed as they were (their owner already has that
-- model; one per model until January). The admin can also put a group away
-- by hand. Both can be undone. Cameras, not texts, are put away: someone
-- who types the same text later still shows.

create table app_private.camera_match_hidden (
  camera_id bigint primary key references public.cameras(id) on delete cascade,
  batch uuid not null,
  hidden_by uuid,
  hidden_at timestamptz not null default now()
);
create index camera_match_hidden_batch_idx on app_private.camera_match_hidden (batch);
revoke all on app_private.camera_match_hidden from public, anon, authenticated;

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
    select c.maker, c.model, count(*), count(distinct c.owner_user_id),
           app_private.camera_text_suggestion(c.maker, c.model)
      from public.cameras c
     where c.camera_model_id is null
       and not exists (select 1 from app_private.camera_match_hidden h where h.camera_id = c.id)
     group by c.maker, c.model
     order by lower(coalesce(c.maker, '')), lower(coalesce(c.model, ''));
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
     and c.model is not distinct from p_model
     and not exists (select 1 from app_private.camera_match_hidden h where h.camera_id = c.id);
  if v_ids is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  v_n := app_private.match_cameras(v_ids, p_model_id, v_batch, v_admin);
  -- The group is settled: the ones left wait for January out of the list.
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

-- Puts a group away by hand, without linking it.
create function public.admin_hide_unmatched(p_maker text, p_model text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_batch uuid := gen_random_uuid();
  v_n integer;
begin
  insert into app_private.camera_match_hidden (camera_id, batch, hidden_by)
  select c.id, v_batch, v_admin
    from public.cameras c
   where c.camera_model_id is null
     and c.maker is not distinct from p_maker
     and c.model is not distinct from p_model
  on conflict (camera_id) do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  return jsonb_build_object('batch', v_batch, 'hidden', v_n);
end;
$$;

-- Undoes a link or a put-away: the cameras are as they were and in the list.
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
  return v_n;
end;
$$;

revoke all on function public.admin_hide_unmatched(text, text) from public, anon;
grant execute on function public.admin_hide_unmatched(text, text) to authenticated;
