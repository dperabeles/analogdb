-- ANA-173: tablas, reglas y lecturas del inventario de film.
--
-- Una compra por alta (precio por unidad) y una fila por rollo físico. El
-- precio no separa líneas: una línea es película + formato + caducidad, y sin
-- fecha, la condición declarada. Nada aquí escribe por la app: lo hacen las
-- funciones de las migraciones siguientes.

-- Caducidad impresa: {year} o {year, month}, como rolls.expiration_date.
create function app_private.normalize_expiration(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_year numeric;
  v_month numeric;
begin
  if p is null or p = 'null'::jsonb then
    return null;
  end if;
  if jsonb_typeof(p) <> 'object' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  if exists (select 1 from jsonb_object_keys(p) k where k not in ('year', 'month'))
     or jsonb_typeof(p -> 'year') is distinct from 'number'
     or coalesce(jsonb_typeof(p -> 'month'), 'null') not in ('number', 'null') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  v_year := (p ->> 'year')::numeric;
  if jsonb_typeof(p -> 'month') = 'number' then
    v_month := (p ->> 'month')::numeric;
  end if;
  if v_year <> trunc(v_year) or v_year not between 1000 and 9999
     or (v_month is not null and (v_month <> trunc(v_month) or v_month not between 1 and 12)) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  if v_month is null then
    return jsonb_build_object('year', v_year::integer);
  end if;
  return jsonb_build_object('year', v_year::integer, 'month', v_month::integer);
end;
$$;

-- Con fecha, vence al terminar el periodo impreso; sin fecha, manda lo
-- declarado. La fecha gana aunque se haya declarado otra cosa.
create function app_private.film_unit_expired(
  p_expiration jsonb, p_declared_fresh boolean, p_on date
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_expiration is null then not coalesce(p_declared_fresh, true)
    when jsonb_typeof(p_expiration -> 'month') = 'number' then
      p_on > (make_date((p_expiration ->> 'year')::integer, (p_expiration ->> 'month')::integer, 1)
              + interval '1 month' - interval '1 day')::date
    else p_on > make_date((p_expiration ->> 'year')::integer, 12, 31)
  end
$$;

-- La fecha local del dispositivo se acepta a un día de la del servidor.
create function app_private.check_local_date(p_today date)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_today is null or abs(p_today - current_date) > 1 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
end;
$$;

create table public.film_purchases (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  film_stock_id bigint not null references public.film_stocks(id),
  format integer not null check (format in (35, 120, 110)),
  quantity integer not null check (quantity between 1 and 9999),
  unit_price_minor bigint check (unit_price_minor between 0 and 1000000000000),
  currency char(3) references public.currencies(code),
  purchased_on date,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint film_purchases_price_has_currency
    check ((unit_price_minor is null) = (currency is null))
);
create index film_purchases_owner_user_id_idx on public.film_purchases(owner_user_id);
create index film_purchases_film_stock_id_idx on public.film_purchases(film_stock_id);
create index film_purchases_currency_idx on public.film_purchases(currency);

-- Una fila por rollo físico. Nunca se borra desde la app: cambia de estado.
-- Una unidad cargada conserva loaded_on aunque su rollo se borre.
create table public.film_units (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  purchase_id uuid references public.film_purchases(id),
  film_stock_id bigint not null references public.film_stocks(id),
  format integer not null check (format in (35, 120, 110)),
  expiration_date jsonb,
  declared_fresh boolean not null default true,
  status text not null default 'available'
    check (status in ('available', 'loaded', 'removed')),
  roll_id bigint references public.rolls(id) on delete set null,
  loaded_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint film_units_load_state check (
    (status = 'loaded' and loaded_on is not null)
    or (status <> 'loaded' and roll_id is null and loaded_on is null)
  ),
  constraint film_units_expiration_shape check (
    expiration_date is null
    or app_private.normalize_expiration(expiration_date) = expiration_date
  )
);
create index film_units_line_idx
  on public.film_units(owner_user_id, film_stock_id, format, status);
create index film_units_purchase_id_idx on public.film_units(purchase_id);
create index film_units_film_stock_id_idx on public.film_units(film_stock_id);
create index film_units_roll_id_idx on public.film_units(roll_id);

create trigger film_purchases_touch before update on public.film_purchases
for each row execute function public.touch_updated_at();
create trigger film_units_touch before update on public.film_units
for each row execute function public.touch_updated_at();

create trigger zz_archivar_borrado before delete on public.film_purchases
for each row execute function public.archivar_fila_borrada();
create trigger zz_archivar_borrado before delete on public.film_units
for each row execute function public.archivar_fila_borrada();
create trigger zz_frenar_masivo after delete on public.film_purchases
referencing old table as borradas
for each statement execute function public.frenar_borrado_masivo();
create trigger zz_frenar_masivo after delete on public.film_units
referencing old table as borradas
for each statement execute function public.frenar_borrado_masivo();

alter table public.film_purchases enable row level security;
alter table public.film_units enable row level security;

create policy film_purchases_select_own on public.film_purchases
for select to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'
  )
);
create policy film_units_select_own on public.film_units
for select to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'
  )
);

revoke all on public.film_purchases, public.film_units from anon;
revoke insert, update, delete, truncate on public.film_purchases, public.film_units from authenticated;
grant select on public.film_purchases, public.film_units to authenticated;

-- La única definición de «línea»: corrección, carga y corrección de caducidad
-- la usan todas.
create function app_private.unit_in_line(
  u public.film_units,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean
)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_expiration jsonb := app_private.normalize_expiration(p_expiration_date);
begin
  return u.film_stock_id = p_film_stock_id
     and u.format = p_format
     and u.expiration_date is not distinct from v_expiration
     and (v_expiration is not null or u.declared_fresh = coalesce(p_declared_fresh, true));
end;
$$;

revoke all on function app_private.normalize_expiration(jsonb) from public, anon, authenticated;
revoke all on function app_private.film_unit_expired(jsonb, boolean, date) from public, anon, authenticated;
revoke all on function app_private.check_local_date(date) from public, anon, authenticated;
revoke all on function app_private.unit_in_line(public.film_units, bigint, integer, jsonb, boolean)
  from public, anon, authenticated;

-- Existencia disponible por línea, con el resumen de precios por moneda. Las
-- monedas nunca se mezclan; la condición de hoy la calcula la app con su fecha.
create view public.film_inventory_lines with (security_invoker = true) as
with available_units as (
  select u.owner_user_id, u.film_stock_id, u.format, u.expiration_date,
         case when u.expiration_date is null then u.declared_fresh end as line_declared_fresh,
         p.unit_price_minor, p.currency
  from public.film_units u
  left join public.film_purchases p on p.id = u.purchase_id
  where u.status = 'available'
),
per_currency as (
  select owner_user_id, film_stock_id, format, expiration_date, line_declared_fresh, currency,
         count(*)::integer as units,
         min(unit_price_minor) as min_minor,
         max(unit_price_minor) as max_minor,
         round(avg(unit_price_minor))::bigint as avg_minor
  from available_units
  where currency is not null
  group by owner_user_id, film_stock_id, format, expiration_date, line_declared_fresh, currency
)
select l.owner_user_id, l.film_stock_id, l.format, l.expiration_date, l.line_declared_fresh,
       count(*)::integer as available,
       (count(*) filter (where l.currency is null))::integer as unpriced,
       coalesce((
         select jsonb_agg(jsonb_build_object(
                  'currency', c.currency, 'units', c.units, 'min_minor', c.min_minor,
                  'max_minor', c.max_minor, 'avg_minor', c.avg_minor) order by c.currency)
         from per_currency c
         where c.owner_user_id = l.owner_user_id
           and c.film_stock_id = l.film_stock_id
           and c.format = l.format
           and c.expiration_date is not distinct from l.expiration_date
           and c.line_declared_fresh is not distinct from l.line_declared_fresh
       ), '[]'::jsonb) as prices
from available_units l
group by l.owner_user_id, l.film_stock_id, l.format, l.expiration_date, l.line_declared_fresh;

-- El registro de compras por película, con lo que queda de cada una.
create view public.film_purchase_status with (security_invoker = true) as
select p.id as purchase_id, p.owner_user_id, p.film_stock_id, p.format, p.quantity,
       p.unit_price_minor, p.currency, p.purchased_on, p.voided_at, p.version, p.created_at,
       (count(u.id) filter (where u.status = 'available'))::integer as available,
       (count(u.id) filter (where u.status = 'loaded'))::integer as loaded,
       (count(u.id) filter (where u.status = 'removed'))::integer as removed
from public.film_purchases p
left join public.film_units u on u.purchase_id = p.id
group by p.id;

-- De qué compra salió el film de cada rollo cargado, y cuánto costó.
create view public.roll_film_origin with (security_invoker = true) as
select u.roll_id, u.id as unit_id, u.purchase_id, u.film_stock_id, u.format,
       u.expiration_date, p.unit_price_minor, p.currency, p.purchased_on, u.loaded_on,
       u.owner_user_id
from public.film_units u
left join public.film_purchases p on p.id = u.purchase_id
where u.status = 'loaded' and u.roll_id is not null;

revoke all on public.film_inventory_lines, public.film_purchase_status, public.roll_film_origin
  from public, anon, authenticated;
grant select on public.film_inventory_lines, public.film_purchase_status, public.roll_film_origin
  to authenticated;
