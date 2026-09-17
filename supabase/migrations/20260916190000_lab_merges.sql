-- Fusionar dos labs que resultaron ser el mismo, sin perder el camino de vuelta.
--
-- ── Qué pidió Diego ──────────────────────────────────────────────────────────
--
--   · "Hazla reversible"
--   · "El lab absorbido déjalo inactivo"
--
-- Es la red de seguridad de la prevención de duplicados: por bueno que sea el
-- emparejado al crear, alguno se colará, y entonces hay que poder unirlos.
--
-- ── Por qué se guarda QUÉ rollos se movieron ─────────────────────────────────
--
-- Deshacer "todos los rollos que apuntan al bueno" sería un desastre: se
-- llevaría también los que YA apuntaban ahí antes de la fusión, y los mandaría
-- a un lab con el que nunca tuvieron nada que ver. Por eso se anota, rollo por
-- rollo y campo por campo, exactamente lo que esta fusión movió.
--
-- ── Lo que NO hace ───────────────────────────────────────────────────────────
--
-- No borra nada. El lab absorbido se queda con todos sus datos, inactivo y
-- apuntando al bueno. Borrarlo pondría los rollos de la gente en `null` (la FK
-- es ON DELETE SET NULL) y eso sí sería irreversible.

-- ── Dónde quedó cada lab absorbido ───────────────────────────────────────────
alter table public.labs
  add column if not exists merged_into_id bigint references public.labs(id);

comment on column public.labs.merged_into_id is
  'Si este lab se fusionó dentro de otro, cuál. Va junto a active=false.';

-- ── El registro de fusiones, que es lo que permite deshacer ──────────────────
create table if not exists public.lab_merges (
  id               bigserial primary key,
  absorbed_lab_id  bigint      not null references public.labs(id),
  canonical_lab_id bigint      not null references public.labs(id),

  -- [{"roll_id": 12, "field": "dev"}, …] — exactamente lo que ESTA fusión
  -- movió. Es la diferencia entre deshacer y hacer más daño.
  moved            jsonb       not null default '[]'::jsonb,

  merged_by        uuid        not null,
  merged_at        timestamptz not null default now(),
  undone_by        uuid,
  undone_at        timestamptz,

  constraint lab_merges_distintos check (absorbed_lab_id <> canonical_lab_id)
);

create index if not exists lab_merges_absorbed_idx on public.lab_merges(absorbed_lab_id);

alter table public.lab_merges enable row level security;

-- Solo admins. Es un registro de moderación: ningún usuario tiene nada que
-- ver aquí, y la escritura pasa únicamente por las RPC de abajo.
drop policy if exists lab_merges_admin_select on public.lab_merges;
create policy lab_merges_admin_select on public.lab_merges
  for select using (public.app_is_admin(auth.uid()));

-- ── Fusionar ────────────────────────────────────────────────────────────────
create or replace function public.admin_merge_labs(
  p_absorbed bigint,
  p_canonical bigint
) returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_movidos jsonb;
  v_id      bigint;
begin
  if not public.app_is_admin(auth.uid()) then
    raise exception 'admin only';
  end if;
  if p_absorbed is null or p_canonical is null or p_absorbed = p_canonical then
    raise exception 'hay que dar dos labs distintos';
  end if;
  if not exists (select 1 from labs where id = p_absorbed) then
    raise exception 'el lab a absorber no existe';
  end if;
  if not exists (select 1 from labs where id = p_canonical) then
    raise exception 'el lab destino no existe';
  end if;

  -- Encadenar fusiones deja el deshacer sin sentido: para revertir la primera
  -- habria que revertir antes la segunda, y nada obliga a hacerlo en ese
  -- orden. Se prohibe, y con eso cada fusion se deshace sola.
  if exists (select 1 from labs where id = p_absorbed and merged_into_id is not null) then
    raise exception 'ese lab ya fue fusionado dentro de otro';
  end if;
  if exists (select 1 from labs where id = p_canonical and merged_into_id is not null) then
    raise exception 'el lab destino esta fusionado dentro de otro: usa ese';
  end if;

  -- Se anota ANTES de mover: despues ya no se sabria cuales eran.
  select coalesce(jsonb_agg(m), '[]'::jsonb) into v_movidos
  from (
    select jsonb_build_object('roll_id', id, 'field', 'dev') as m
    from rolls where dev_lab_id = p_absorbed
    union all
    select jsonb_build_object('roll_id', id, 'field', 'scan')
    from rolls where scan_lab_id = p_absorbed
  ) t;

  update rolls set dev_lab_id  = p_canonical where dev_lab_id  = p_absorbed;
  update rolls set scan_lab_id = p_canonical where scan_lab_id = p_absorbed;

  -- Inactivo, no borrado: borrarlo pondria los rollos en null por la FK.
  update labs
     set active = false,
         merged_into_id = p_canonical
   where id = p_absorbed;

  insert into lab_merges (absorbed_lab_id, canonical_lab_id, moved, merged_by)
  values (p_absorbed, p_canonical, v_movidos, auth.uid())
  returning id into v_id;

  return v_id;
end;
$function$;

-- ── Deshacer ────────────────────────────────────────────────────────────────
create or replace function public.admin_undo_lab_merge(p_merge_id bigint)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_fusion lab_merges%rowtype;
begin
  if not public.app_is_admin(auth.uid()) then
    raise exception 'admin only';
  end if;

  select * into v_fusion from lab_merges where id = p_merge_id;
  if not found then raise exception 'esa fusion no existe'; end if;
  if v_fusion.undone_at is not null then raise exception 'esa fusion ya se deshizo'; end if;

  -- Solo se devuelven los rollos que SIGUEN apuntando al lab bueno en ese
  -- campo. Si alguien cambio el lab de su rollo despues de la fusion, esa
  -- decision es suya y deshacer no la pisa.
  update rolls r
     set dev_lab_id = v_fusion.absorbed_lab_id
    from jsonb_array_elements(v_fusion.moved) e
   where (e->>'field') = 'dev'
     and r.id = (e->>'roll_id')::bigint
     and r.dev_lab_id = v_fusion.canonical_lab_id;

  update rolls r
     set scan_lab_id = v_fusion.absorbed_lab_id
    from jsonb_array_elements(v_fusion.moved) e
   where (e->>'field') = 'scan'
     and r.id = (e->>'roll_id')::bigint
     and r.scan_lab_id = v_fusion.canonical_lab_id;

  update labs
     set active = true,
         merged_into_id = null
   where id = v_fusion.absorbed_lab_id;

  update lab_merges
     set undone_at = now(), undone_by = auth.uid()
   where id = p_merge_id;
end;
$function$;

revoke all on function public.admin_merge_labs(bigint, bigint) from public, anon;
revoke all on function public.admin_undo_lab_merge(bigint) from public, anon;
grant execute on function public.admin_merge_labs(bigint, bigint) to authenticated;
grant execute on function public.admin_undo_lab_merge(bigint) to authenticated;
