-- ANA-152. Additive migration: no historical exposure is backfilled.
-- Optical columns exist in production; IF NOT EXISTS also aligns fresh schemas.
alter table public.lenses add column if not exists is_zoom boolean,
  add column if not exists focal_min integer, add column if not exists focal_max integer,
  add column if not exists max_aperture numeric, add column if not exists max_aperture_tele numeric;

alter table public.roll_exposures
  add column lens_id bigint references public.lenses(id) on delete set null,
  add column lens_source text,
  add column lens_snapshot jsonb;

alter table public.roll_exposures add constraint exposure_lens_contract check (((
  (lens_source is null and lens_id is null and lens_snapshot is null)
  or (lens_source in ('unknown','fixed_camera') and lens_id is null and lens_snapshot is null)
  or (lens_source in ('roll_default','frame_selected') and lens_snapshot is not null
    and jsonb_typeof(lens_snapshot) = 'object'
    and lens_snapshot->'version' = '1'::jsonb
    and jsonb_typeof(lens_snapshot->'display_name') = 'string'
    and length(trim(lens_snapshot->>'display_name')) > 0)
) is true);
-- CHECK treats NULL as passing: explicitly reject unknown sources and absent keys.
alter table public.roll_exposures add constraint exposure_lens_source check (
  lens_source is null or lens_source in ('roll_default','frame_selected','unknown','fixed_camera'));
alter table public.roll_exposures add constraint exposure_lens_snapshot_keys check (
  lens_snapshot is null or (lens_snapshot ? 'version' and lens_snapshot ? 'display_name'));
create index roll_exposures_lens_id_idx on public.roll_exposures(lens_id);

create or replace function public.preserve_exposure_lens()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if TG_OP = 'DELETE' then
    -- Legacy clients do not know a lens-only frame contains data. Reject direct
    -- deletion; parent-roll cascades remain valid because the parent is gone.
    if old.lens_source is not null and exists(select 1 from public.rolls where id=old.roll_id) then
      raise exception 'This frame contains lens metadata; use a lens-aware client' using errcode='23514';
    end if;
    return old;
  end if;
  if TG_OP = 'UPDATE' and old.lens_source is not null and new.lens_source is null then
    new.lens_id := old.lens_id;
    new.lens_source := old.lens_source;
    new.lens_snapshot := old.lens_snapshot;
  end if;
  if new.lens_id is not null then
    if not exists(select 1 from public.lenses l join public.rolls r on r.id=new.roll_id
      where l.id=new.lens_id and l.owner_user_id=r.owner_user_id) then
      raise exception 'Lens must belong to the owner of the roll' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
create trigger aa_preserve_exposure_lens before insert or update or delete
  on public.roll_exposures for each row execute function public.preserve_exposure_lens();
comment on column public.roll_exposures.lens_snapshot is
  'Immutable-at-capture lens description v1; catalogue rename/delete does not rewrite it.';
comment on column public.roll_exposures.lens_source is
  'NULL=legacy/unrecorded; roll_default and frame_selected are confirmed snapshots, not live inheritance.';

-- Preserve deployed column order, grants and security_invoker; append identities
-- so offline clients can resolve the roll lens without guessing from its name.
do $$ declare definition text; begin
  definition := pg_get_viewdef('public.rolls_flat'::regclass,true);
  if position('r.scan_lab_id AS "SCAN LAB ID"' in definition)=0 then
    raise exception 'Unexpected rolls_flat shape';
  end if;
  definition := replace(definition,'r.scan_lab_id AS "SCAN LAB ID"',
    'r.scan_lab_id AS "SCAN LAB ID", r.camera_id AS "CAMERA ID", r.lens_id AS "LENS ID", c.supports_interchangeable_lenses AS "CAMERA INTERCHANGEABLE"');
  definition := replace(definition,'WHERE re.apertura IS NOT NULL',
    'WHERE re.lens_source IS NOT NULL OR coalesce(re.luz_natural,false) OR re.apertura IS NOT NULL');
  if position('re.lens_source IS NOT NULL' in definition)=0 then
    raise exception 'Unexpected frame count expression';
  end if;
  execute 'create or replace view public.rolls_flat with (security_invoker=true) as ' || definition;
end $$;
notify pgrst, 'reload schema';
