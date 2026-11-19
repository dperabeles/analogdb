-- Catálogo de films, base (Fase 2a, Diego 16 y 19-nov).
--
-- · Fabricantes en su propia tabla, moderada como los films: cualquiera
--   propone uno nuevo, el administrador lo aprueba, lo corrige o lo fusiona
--   con otro. «Lucky Film» y «Luckyfilm» son el mismo por su clave. En enero
--   cámaras y lentes usan la misma tabla.
-- · El proceso de cada film (C-41, E-6, ECN-2, B/N u otro), opcional.
-- · Moderación con control total: editar un film pendiente o aprobado,
--   «Fusionar con…» un film elegido y deshacerlo, lo mismo para fabricantes,
--   y editar labs aprobados. Todo queda registrado (quién, cuándo, antes y
--   después) en catalog_changes.
--
-- film_stocks.manufacturer (texto) se conserva: la app, la web y rolls_flat
-- lo leen. Desde aquí siempre es igual al nombre de su fabricante.

-- ── Fabricantes ───────────────────────────────────────────────────────────

-- La misma marca escrita de varias formas tiene una sola clave: minúsculas,
-- sin acentos, sin espacios ni signos (como la clave de labs).
create function app_private.manufacturer_key(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(
    translate(lower(coalesce(p_name, '')),
              'áàäâãéèëêíìïîóòöôõúùüûñç',
              'aaaaaeeeeiiiiooooouuuunc'),
    '[^a-z0-9]', '', 'g')
$$;

create table public.manufacturers (
  id bigint generated always as identity primary key,
  name text not null check (btrim(name) <> '' and length(name) <= 80),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'merged')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  merged_into bigint references public.manufacturers(id),
  constraint manufacturers_merged_has_target check ((status = 'merged') = (merged_into is not null))
);
create unique index manufacturers_approved_key
  on public.manufacturers (app_private.manufacturer_key(name)) where status = 'approved';
create unique index manufacturers_own_key
  on public.manufacturers (created_by, app_private.manufacturer_key(name))
  where status in ('pending', 'rejected');
create index manufacturers_merged_into_idx on public.manufacturers (merged_into);

alter table public.manufacturers enable row level security;
-- Como los films: el catálogo aprobado para todos; lo propuesto, solo para
-- quien lo propuso, hasta que se revisa.
create policy manufacturers_select on public.manufacturers
for select to authenticated
using (
  status = 'approved'
  or (created_by = (select auth.uid()) and status in ('pending', 'rejected'))
  or public.app_is_admin((select auth.uid()))
);
revoke all on public.manufacturers from anon, authenticated;
grant select on public.manufacturers to authenticated;

-- ── Films: fabricante y proceso ───────────────────────────────────────────

alter table public.film_stocks
  add column manufacturer_id bigint references public.manufacturers(id),
  add column process text
    check (process is null or process in ('C-41', 'E-6', 'ECN-2', 'BW', 'OTHER'));
create index film_stocks_manufacturer_id_idx on public.film_stocks (manufacturer_id);

-- Relleno. Un fabricante aprobado por cada clave con algún film aprobado, con
-- la forma más usada entre los aprobados; el resto, pendiente de quien lo
-- escribió.
insert into public.manufacturers (name, status, reviewed_at)
select spelling, 'approved', now()
from (
  select app_private.manufacturer_key(manufacturer) as k,
         mode() within group (order by btrim(manufacturer)) as spelling
  from public.film_stocks
  where status = 'approved' and app_private.manufacturer_key(manufacturer) <> ''
  group by 1
) a;

insert into public.manufacturers (name, status, created_by)
select min(btrim(f.manufacturer)), 'pending', f.created_by
from public.film_stocks f
where app_private.manufacturer_key(f.manufacturer) <> ''
  and not exists (
    select 1 from public.manufacturers m
    where m.status = 'approved'
      and app_private.manufacturer_key(m.name) = app_private.manufacturer_key(f.manufacturer))
group by app_private.manufacturer_key(f.manufacturer), f.created_by;

update public.film_stocks f
   set manufacturer_id = coalesce(
     (select m.id from public.manufacturers m
       where m.status = 'approved'
         and app_private.manufacturer_key(m.name) = app_private.manufacturer_key(f.manufacturer)),
     (select m.id from public.manufacturers m
       where m.status = 'pending'
         and m.created_by is not distinct from f.created_by
         and app_private.manufacturer_key(m.name) = app_private.manufacturer_key(f.manufacturer)));

do $$
begin
  if exists (select 1 from public.film_stocks where manufacturer_id is null) then
    raise exception 'film_stocks sin fabricante tras el relleno: %',
      (select count(*) from public.film_stocks where manufacturer_id is null);
  end if;
end $$;

-- El texto queda con el nombre canónico (en producción, solo la sugerencia
-- pendiente «Lucky Film» pasa a «Luckyfilm»).
update public.film_stocks f
   set manufacturer = m.name
  from public.manufacturers m
 where m.id = f.manufacturer_id and f.manufacturer is distinct from m.name;

alter table public.film_stocks alter column manufacturer_id set not null;

-- El fabricante de un film nuevo o corregido. Por clave: el aprobado; si no,
-- el pendiente o rechazado de quien escribe; si no, uno nuevo (aprobado si el
-- film nace aprobado, como en una migración de catálogo).
create function app_private.manufacturer_for(p_name text, p_owner uuid, p_approved boolean)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := app_private.manufacturer_key(p_name);
  v_id bigint;
begin
  if v_key = '' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('manufacturer:' || v_key, 0));
  select id into v_id from public.manufacturers
   where status = 'approved' and app_private.manufacturer_key(name) = v_key;
  if found then return v_id; end if;
  if p_owner is not null then
    select id into v_id from public.manufacturers
     where created_by = p_owner and status in ('pending', 'rejected')
       and app_private.manufacturer_key(name) = v_key;
    if found then return v_id; end if;
  end if;
  insert into public.manufacturers (name, status, created_by, reviewed_at)
  values (regexp_replace(btrim(p_name), '\s+', ' ', 'g'),
          case when p_approved and p_owner is null then 'approved' else 'pending' end,
          p_owner,
          case when p_approved and p_owner is null then now() end)
  returning id into v_id;
  return v_id;
end;
$$;

create function app_private.film_stocks_manufacturer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.manufacturer_id is null
     or tg_op = 'UPDATE' and new.manufacturer is distinct from old.manufacturer
        and new.manufacturer_id is not distinct from old.manufacturer_id then
    new.manufacturer_id := app_private.manufacturer_for(
      new.manufacturer, new.created_by, new.status = 'approved');
  end if;
  select m.name into new.manufacturer
    from public.manufacturers m where m.id = new.manufacturer_id;
  if new.manufacturer is null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  return new;
end;
$$;

create trigger film_stocks_manufacturer
before insert or update of manufacturer, manufacturer_id on public.film_stocks
for each row execute function app_private.film_stocks_manufacturer();

-- ── Registro de cambios del catálogo ──────────────────────────────────────

create table public.catalog_changes (
  id bigint generated always as identity primary key,
  entity text not null check (entity in ('film_stock', 'manufacturer', 'lab')),
  entity_id bigint not null,
  action text not null check (action in ('edit', 'merge')),
  target_id bigint,
  before jsonb not null default '{}',
  after jsonb not null default '{}',
  moved jsonb not null default '{}',
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  undone_by uuid references auth.users(id) on delete set null,
  undone_at timestamptz,
  constraint catalog_changes_merge_target check ((action = 'merge') = (target_id is not null))
);
create index catalog_changes_entity_idx on public.catalog_changes (entity, entity_id);
alter table public.catalog_changes enable row level security;
create policy catalog_changes_admin_select on public.catalog_changes
for select to authenticated using (public.app_is_admin((select auth.uid())));
revoke all on public.catalog_changes from anon, authenticated;
grant select on public.catalog_changes to authenticated;

create function app_private.require_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P1201';
  end if;
  if not public.app_is_admin(auth.uid()) then
    raise exception 'not_admin' using errcode = 'P1205';
  end if;
  return auth.uid();
end;
$$;

-- Una cuenta aprobada que propone algo al catálogo.
create function app_private.require_approved()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P1201';
  end if;
  if not exists (select 1 from public.profiles p
                 where p.user_id = auth.uid() and p.status = 'approved') then
    raise exception 'profile_not_approved' using errcode = 'P1202';
  end if;
  return auth.uid();
end;
$$;

-- ── Proponer ──────────────────────────────────────────────────────────────

create function public.propose_manufacturer(p_name text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.require_approved();
begin
  if p_name is null or length(btrim(p_name)) > 80 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  return app_private.manufacturer_for(p_name, v_user, false);
end;
$$;

create function public.propose_film_stock(
  p_manufacturer_id bigint,
  p_name text,
  p_iso integer default null,
  p_type text default null,
  p_process text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.require_approved();
  v_maker public.manufacturers;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_key text;
  v_id bigint;
begin
  select * into v_maker from public.manufacturers m
   where m.id = p_manufacturer_id
     and (m.status = 'approved'
          or (m.created_by = v_user and m.status in ('pending', 'rejected')));
  if not found
     or v_name = '' or length(v_name) > 80
     or (p_iso is not null and p_iso not between 1 and 25600)
     or (p_type is not null and p_type not in ('COLOR', 'B/W', 'SLIDE'))
     or (p_process is not null and p_process not in ('C-41', 'E-6', 'ECN-2', 'BW', 'OTHER')) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  v_key := app_private.film_stock_key(v_maker.name, v_name);
  perform pg_advisory_xact_lock(hashtextextended('film_stock:' || v_key, 0));
  select s.id into v_id from public.film_stocks s
   where s.status = 'approved' and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
  if found then return v_id; end if;
  select s.id into v_id from public.film_stocks s
   where s.created_by = v_user and s.status in ('pending', 'rejected')
     and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
  if found then return v_id; end if;
  insert into public.film_stocks
    (manufacturer, manufacturer_id, name, iso, type, process, in_catalog, status, created_by)
  values (v_maker.name, v_maker.id, v_name, p_iso, p_type, p_process, false, 'pending', v_user)
  returning id into v_id;
  return v_id;
end;
$$;

-- La forma de siempre, por texto (la web): busca con el nombre canónico del
-- fabricante, para encontrar «Luckyfilm C400» cuando alguien escribe
-- «Lucky Film C400».
create or replace function public.ensure_film_stock(
  p_manufacturer text,
  p_name text,
  p_iso integer default null,
  p_type text default null
)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_maker text := coalesce(
    (select m.name from public.manufacturers m
      where m.status = 'approved'
        and app_private.manufacturer_key(m.name) = app_private.manufacturer_key(p_manufacturer)),
    btrim(coalesce(p_manufacturer, '')));
  v_key text := app_private.film_stock_key(v_maker, p_name);
  v_id bigint;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = 'P1101';
  end if;
  if v_key = '' or app_private.manufacturer_key(v_maker) = '' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  -- Waits for a review of this name in progress, so it finds the approved
  -- film instead of leaving a private copy beside it.
  perform pg_advisory_xact_lock(hashtextextended('film_stock:' || v_key, 0));
  for i in 1..2 loop
    select s.id into v_id from public.film_stocks s
     where s.status = 'approved'
       and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
    if found then return v_id; end if;
    select s.id into v_id from public.film_stocks s
     where s.created_by = auth.uid() and s.status in ('pending', 'rejected')
       and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
    if found then return v_id; end if;
    begin
      insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
      values (v_maker, btrim(coalesce(p_name, '')), p_iso, p_type, false)
      returning id into v_id;
      return v_id;
    exception when unique_violation then
      -- Another request made it first: read it again.
      null;
    end;
  end loop;
  raise exception 'stock_conflict' using errcode = 'P1104';
end;
$$;

-- ── Administrar films ─────────────────────────────────────────────────────

create function app_private.film_stock_snapshot(f public.film_stocks)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('manufacturer_id', f.manufacturer_id, 'manufacturer', f.manufacturer,
    'name', f.name, 'iso', f.iso, 'type', f.type, 'process', f.process, 'status', f.status,
    'merged_into', f.merged_into, 'reviewed_by', f.reviewed_by, 'reviewed_at', f.reviewed_at)
$$;

-- Corrige un film, pendiente o aprobado. Uno aprobado lo ven todos: el panel
-- confirma antes, y aquí queda quién y cuándo.
create function public.admin_film_stock_update(
  p_id bigint,
  p_manufacturer_id bigint,
  p_name text,
  p_iso integer,
  p_type text,
  p_process text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_film public.film_stocks;
  v_maker public.manufacturers;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_before jsonb;
  v_change bigint;
begin
  select * into v_film from public.film_stocks where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  v_before := app_private.film_stock_snapshot(v_film);
  if v_film.status not in ('pending', 'approved', 'rejected') then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  select * into v_maker from public.manufacturers m
   where m.id = p_manufacturer_id
     and (m.status = 'approved'
          or (m.status in ('pending', 'rejected') and m.created_by = v_film.created_by));
  if not found
     or v_name = '' or length(v_name) > 80
     or (p_iso is not null and p_iso not between 1 and 25600)
     or (p_type is not null and p_type not in ('COLOR', 'B/W', 'SLIDE'))
     or (p_process is not null and p_process not in ('C-41', 'E-6', 'ECN-2', 'BW', 'OTHER')) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  begin
    update public.film_stocks
       set manufacturer_id = v_maker.id, name = v_name, iso = p_iso, type = p_type,
           process = p_process
     where id = p_id
    returning * into v_film;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  insert into public.catalog_changes (entity, entity_id, action, before, after, changed_by)
  values ('film_stock', p_id, 'edit', v_before, app_private.film_stock_snapshot(v_film), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

-- Lo que una fusión movería, para confirmarla antes.
create function public.admin_film_stock_merge_preview(p_from bigint, p_into bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.require_admin();
  return jsonb_build_object(
    'rolls', (select count(*) from public.rolls where film_stock_id = p_from),
    'units', (select count(*) from public.film_units where film_stock_id = p_from),
    'purchases', (select count(*) from public.film_purchases where film_stock_id = p_from),
    'favorites', (select count(*) from public.profile_preferences where favorite_film_stock_id = p_from),
    'accounts', (select count(distinct o) from (
        select owner_user_id as o from public.rolls where film_stock_id = p_from
        union select owner_user_id from public.film_units where film_stock_id = p_from) x));
end;
$$;

-- «Fusionar con…»: todo lo que usa [p_from] pasa a [p_into], que debe estar
-- aprobado. Se anota qué se movió antes de moverlo, para poder deshacerlo.
-- No se encadenan, como en labs: cada fusión se deshace sola.
create function public.admin_film_stock_merge(p_from bigint, p_into bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_from public.film_stocks;
  v_into public.film_stocks;
  v_moved jsonb;
  v_change bigint;
begin
  if p_from is null or p_into is null or p_from = p_into then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_from from public.film_stocks where id = p_from for update;
  select * into v_into from public.film_stocks where id = p_into for update;
  if v_from.id is null or v_into.id is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_from.status = 'merged' or v_into.status <> 'approved' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;

  v_moved := jsonb_build_object(
    'rolls', coalesce((select jsonb_agg(id) from public.rolls where film_stock_id = p_from), '[]'),
    'units', coalesce((select jsonb_agg(id) from public.film_units where film_stock_id = p_from), '[]'),
    'purchases', coalesce((select jsonb_agg(id) from public.film_purchases where film_stock_id = p_from), '[]'),
    'favorites', coalesce((select jsonb_agg(user_id) from public.profile_preferences
                           where favorite_film_stock_id = p_from), '[]'));

  perform app_private.merge_film_stock(p_from, p_into);

  insert into public.catalog_changes
    (entity, entity_id, action, target_id, before, after, moved, changed_by)
  values ('film_stock', p_from, 'merge', p_into, app_private.film_stock_snapshot(v_from),
          app_private.film_stock_snapshot((select f from public.film_stocks f where f.id = p_from)),
          v_moved, v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

-- Deshacer una fusión: el film vuelve a como estaba, y vuelve solo lo que
-- sigue en el destino; lo que alguien cambió después es decisión suya.
create function public.admin_film_stock_undo_merge(p_change_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_change public.catalog_changes;
  v_from bigint;
  v_into bigint;
begin
  select * into v_change from public.catalog_changes
   where id = p_change_id and entity = 'film_stock' and action = 'merge'
   for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_change.undone_at is not null then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  v_from := v_change.entity_id;
  v_into := v_change.target_id;

  -- Primero el film, o el disparador de rollos lo seguiría al destino.
  update public.film_stocks
     set status = v_change.before ->> 'status',
         merged_into = (v_change.before ->> 'merged_into')::bigint,
         reviewed_by = (v_change.before ->> 'reviewed_by')::uuid,
         reviewed_at = (v_change.before ->> 'reviewed_at')::timestamptz
   where id = v_from and status = 'merged' and merged_into = v_into;
  if not found then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;

  update public.rolls set film_stock_id = v_from
   where film_stock_id = v_into
     and id in (select (x)::bigint from jsonb_array_elements_text(v_change.moved -> 'rolls') x);
  update public.film_units set film_stock_id = v_from, version = version + 1
   where film_stock_id = v_into
     and id in (select (x)::uuid from jsonb_array_elements_text(v_change.moved -> 'units') x);
  update public.film_purchases set film_stock_id = v_from
   where film_stock_id = v_into
     and id in (select (x)::uuid from jsonb_array_elements_text(v_change.moved -> 'purchases') x);
  update public.profile_preferences set favorite_film_stock_id = v_from
   where favorite_film_stock_id = v_into
     and user_id in (select (x)::uuid from jsonb_array_elements_text(v_change.moved -> 'favorites') x);

  update public.catalog_changes set undone_at = now(), undone_by = v_admin
   where id = p_change_id;
end;
$$;

-- ── Administrar fabricantes ───────────────────────────────────────────────

create function app_private.manufacturer_snapshot(m public.manufacturers)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('name', m.name, 'status', m.status, 'merged_into', m.merged_into,
    'reviewed_by', m.reviewed_by, 'reviewed_at', m.reviewed_at)
$$;

-- Los films de un fabricante llevan su nombre: se copia tras renombrar o
-- fusionar. Si así dos films aprobados quedan con la misma clave, primero hay
-- que fusionar esos films.
create function app_private.manufacturer_films_follow(p_maker bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.film_stocks f
     set manufacturer = m.name
    from public.manufacturers m
   where m.id = p_maker and f.manufacturer_id = p_maker
     and f.manufacturer is distinct from m.name;
exception when unique_violation then
  raise exception 'name_taken' using errcode = 'P1113';
end;
$$;

-- Aprobar o rechazar una propuesta. Aprobar una cuya clave ya existe la
-- fusiona con la aprobada (registrado, se puede deshacer).
create function public.admin_manufacturer_review(p_id bigint, p_decision text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_maker public.manufacturers;
  v_target bigint;
begin
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_maker from public.manufacturers where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_maker.status not in ('pending', 'rejected') then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('manufacturer:' || app_private.manufacturer_key(v_maker.name), 0));
  if p_decision = 'rejected' then
    update public.manufacturers
       set status = 'rejected', reviewed_by = v_admin, reviewed_at = now()
     where id = p_id;
    return null;
  end if;
  select id into v_target from public.manufacturers
   where status = 'approved'
     and app_private.manufacturer_key(name) = app_private.manufacturer_key(v_maker.name);
  if found then
    return public.admin_manufacturer_merge(p_id, v_target);
  end if;
  update public.manufacturers
     set status = 'approved', reviewed_by = v_admin, reviewed_at = now()
   where id = p_id;
  return null;
end;
$$;

-- Corregir el nombre (también de uno aprobado). Sus films lo siguen.
create function public.admin_manufacturer_update(p_id bigint, p_name text)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_before public.manufacturers;
  v_after public.manufacturers;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_change bigint;
begin
  if v_name = '' or length(v_name) > 80 or app_private.manufacturer_key(v_name) = '' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_before from public.manufacturers where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_before.status = 'merged' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  begin
    update public.manufacturers set name = v_name where id = p_id returning * into v_after;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  perform app_private.manufacturer_films_follow(p_id);
  insert into public.catalog_changes (entity, entity_id, action, before, after, changed_by)
  values ('manufacturer', p_id, 'edit', app_private.manufacturer_snapshot(v_before),
          app_private.manufacturer_snapshot(v_after), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

-- «Fusionar con…» para fabricantes («Fuji» → «Fujifilm»): sus films pasan al
-- destino, que debe estar aprobado. Registrado y reversible.
create function public.admin_manufacturer_merge(p_from bigint, p_into bigint)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_from public.manufacturers;
  v_into public.manufacturers;
  v_films jsonb;
  v_change bigint;
begin
  if p_from is null or p_into is null or p_from = p_into then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_from from public.manufacturers where id = p_from for update;
  select * into v_into from public.manufacturers where id = p_into for update;
  if v_from.id is null or v_into.id is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_from.status = 'merged' or v_into.status <> 'approved' then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  v_films := coalesce((select jsonb_agg(id) from public.film_stocks where manufacturer_id = p_from), '[]');
  begin
    update public.film_stocks set manufacturer_id = p_into where manufacturer_id = p_from;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  update public.manufacturers
     set status = 'merged', merged_into = p_into, reviewed_by = v_admin, reviewed_at = now()
   where id = p_from;
  insert into public.catalog_changes
    (entity, entity_id, action, target_id, before, after, moved, changed_by)
  values ('manufacturer', p_from, 'merge', p_into, app_private.manufacturer_snapshot(v_from),
          app_private.manufacturer_snapshot((select m from public.manufacturers m where m.id = p_from)),
          jsonb_build_object('films', v_films), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

create function public.admin_manufacturer_undo_merge(p_change_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_change public.catalog_changes;
begin
  select * into v_change from public.catalog_changes
   where id = p_change_id and entity = 'manufacturer' and action = 'merge'
   for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_change.undone_at is not null then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  update public.manufacturers
     set status = v_change.before ->> 'status', merged_into = null,
         reviewed_by = (v_change.before ->> 'reviewed_by')::uuid,
         reviewed_at = (v_change.before ->> 'reviewed_at')::timestamptz
   where id = v_change.entity_id and status = 'merged' and merged_into = v_change.target_id;
  if not found then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  begin
    update public.film_stocks set manufacturer_id = v_change.entity_id
     where manufacturer_id = v_change.target_id
       and id in (select (x)::bigint from jsonb_array_elements_text(v_change.moved -> 'films') x);
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  update public.catalog_changes set undone_at = now(), undone_by = v_admin
   where id = p_change_id;
end;
$$;

-- ── Administrar labs ──────────────────────────────────────────────────────

-- Corregir un lab, también uno aprobado. Solo los campos de su ficha; el
-- estado se cambia con review_lab y la fusión con admin_merge_labs.
create function public.admin_lab_update(p_id bigint, p_fields jsonb)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_before public.labs;
  v_after public.labs;
  v_allowed constant text[] := array['name', 'city', 'country', 'country_code', 'self_processed',
    'instagram', 'place_id', 'address', 'website', 'accepts_mail', 'services', 'formats', 'processes'];
  v_key text;
  v_change bigint;
begin
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' or p_fields = '{}' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  for v_key in select jsonb_object_keys(p_fields) loop
    if not v_key = any (v_allowed) then
      raise exception 'invalid_input' using errcode = 'P1103';
    end if;
  end loop;
  if p_fields ? 'name' and btrim(coalesce(p_fields ->> 'name', '')) = '' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  select * into v_before from public.labs where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  begin
    update public.labs l
       set (name, city, country, country_code, self_processed, instagram, place_id, address,
            website, accepts_mail, services, formats, processes) =
           (select r.name, r.city, r.country, r.country_code, r.self_processed, r.instagram,
                   r.place_id, r.address, r.website, r.accepts_mail, r.services, r.formats,
                   r.processes
              from jsonb_populate_record(l, p_fields) r)
     where l.id = p_id
    returning * into v_after;
  exception
    when unique_violation then
      raise exception 'name_taken' using errcode = 'P1113';
    -- Fuera del vocabulario de formatos, servicios o procesos, o un dato con
    -- otra forma: lo mismo que cualquier dato inválido.
    when check_violation or invalid_text_representation or datatype_mismatch
         or invalid_parameter_value then
      raise exception 'invalid_input' using errcode = 'P1103';
  end;
  insert into public.catalog_changes (entity, entity_id, action, before, after, changed_by)
  values ('lab', p_id, 'edit', to_jsonb(v_before) - 'match_key', to_jsonb(v_after) - 'match_key',
          v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

-- ── Permisos ──────────────────────────────────────────────────────────────

-- Pura y sin datos; ensure_film_stock la usa con los permisos de quien llama,
-- como film_stock_key.
revoke all on function app_private.manufacturer_key(text) from public, anon;
grant execute on function app_private.manufacturer_key(text) to authenticated;
revoke all on function app_private.manufacturer_for(text, uuid, boolean) from public, anon, authenticated;
revoke all on function app_private.film_stocks_manufacturer() from public, anon, authenticated;
revoke all on function app_private.require_admin() from public, anon, authenticated;
revoke all on function app_private.require_approved() from public, anon, authenticated;
revoke all on function app_private.film_stock_snapshot(public.film_stocks) from public, anon, authenticated;
revoke all on function app_private.manufacturer_snapshot(public.manufacturers) from public, anon, authenticated;
revoke all on function app_private.manufacturer_films_follow(bigint) from public, anon, authenticated;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.propose_manufacturer(text)',
    'public.propose_film_stock(bigint, text, integer, text, text)',
    'public.admin_film_stock_update(bigint, bigint, text, integer, text, text)',
    'public.admin_film_stock_merge_preview(bigint, bigint)',
    'public.admin_film_stock_merge(bigint, bigint)',
    'public.admin_film_stock_undo_merge(bigint)',
    'public.admin_manufacturer_review(bigint, text)',
    'public.admin_manufacturer_update(bigint, text)',
    'public.admin_manufacturer_merge(bigint, bigint)',
    'public.admin_manufacturer_undo_merge(bigint)',
    'public.admin_lab_update(bigint, jsonb)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
