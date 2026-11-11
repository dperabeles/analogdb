-- Costos (ANA-184), parte 1: base de costos y precio del film de los rollos
-- que no salieron del inventario. La compra vive en film_purchases con
-- origin = 'roll', una unidad y sin existencia, ligada a su rollo.

insert into app_private.feature_flags (feature) values ('costs');

create function app_private.costs_writer()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = 'P1101';
  end if;
  if not app_private.feature_enabled(v_user, 'costs') then
    raise exception 'not_enabled' using errcode = 'P1102';
  end if;
  return v_user;
end;
$$;
revoke all on function app_private.costs_writer() from public, anon, authenticated;

-- Compra del inventario o precio del film de un rollo. Una compra 'roll' no
-- tiene unidades; su película y formato se toman del rollo mientras existe.
alter table public.film_purchases
  add column origin text not null default 'inventory' check (origin in ('inventory', 'roll')),
  add column roll_id bigint references public.rolls(id) on delete set null,
  alter column film_stock_id drop not null,
  alter column format drop not null,
  drop constraint film_purchases_format_check,
  add constraint film_purchases_inventory_line
    check (origin = 'roll' or (film_stock_id is not null and format in (35, 120, 110))),
  add constraint film_purchases_roll_only_for_roll check (origin = 'roll' or roll_id is null),
  add constraint film_purchases_roll_single_unit check (origin = 'inventory' or quantity = 1);
create unique index film_purchases_active_roll_uidx on public.film_purchases(roll_id)
  where roll_id is not null and voided_at is null;

-- Un rollo tiene a lo más un origen de film: una unidad o una compra 'roll'.
drop index public.film_units_roll_id_idx;
create unique index film_units_roll_id_uidx on public.film_units(roll_id)
  where roll_id is not null;

create or replace view public.film_purchase_status with (security_invoker = true) as
select p.id as purchase_id, p.owner_user_id, p.film_stock_id, p.format, p.quantity,
       p.unit_price_minor, p.currency, p.purchased_on, p.voided_at, p.version, p.created_at,
       (count(u.id) filter (where u.status = 'available'))::integer as available,
       (count(u.id) filter (where u.status = 'loaded'))::integer as loaded,
       (count(u.id) filter (where u.status = 'removed'))::integer as removed
from public.film_purchases p
left join public.film_units u on u.purchase_id = p.id
where p.origin = 'inventory'
group by p.id;

create or replace view public.roll_film_origin with (security_invoker = true) as
select u.roll_id, u.id as unit_id, u.purchase_id, u.film_stock_id, u.format,
       u.expiration_date, p.unit_price_minor, p.currency, p.purchased_on, u.loaded_on,
       u.owner_user_id, 'inventory'::text as origin, p.version as purchase_version
from public.film_units u
left join public.film_purchases p on p.id = u.purchase_id
where u.status = 'loaded' and u.roll_id is not null
union all
select r.id, null::uuid, p.id, r.film_stock_id, r.format,
       r.expiration_date::jsonb, p.unit_price_minor, p.currency, p.purchased_on, null::date,
       p.owner_user_id, 'roll'::text, p.version
from public.film_purchases p
join public.rolls r on r.id = p.roll_id
where p.origin = 'roll' and p.voided_at is null;

-- Las compras 'roll' se editan desde la Ficha, no desde el inventario.
create or replace function public.inventory_update_purchase(
  p_command_id uuid,
  p_purchase_id uuid,
  p_expected_version integer,
  p_unit_price_minor bigint,
  p_currency text,
  p_purchased_on date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.inventory_writer();
  v_request jsonb := jsonb_build_object(
    'purchase_id', p_purchase_id, 'expected_version', p_expected_version,
    'unit_price_minor', p_unit_price_minor, 'currency', p_currency,
    'purchased_on', p_purchased_on);
  v_replay jsonb;
  v_purchase public.film_purchases%rowtype;
  v_version integer;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'update_purchase', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  select * into v_purchase from public.film_purchases
  where id = p_purchase_id and owner_user_id = v_user and origin = 'inventory'
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_purchase.voided_at is not null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  perform app_private.check_purchase_fields(p_unit_price_minor, p_currency, p_purchased_on);
  if v_purchase.version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  update public.film_purchases
     set unit_price_minor = p_unit_price_minor, currency = p_currency,
         purchased_on = p_purchased_on, version = version + 1
   where id = p_purchase_id
  returning version into v_version;

  return app_private.command_record(v_user, p_command_id, 'update_purchase', v_request,
    jsonb_build_object('purchase_id', p_purchase_id, 'version', v_version));
end;
$$;

create or replace function public.inventory_void_purchase(
  p_command_id uuid,
  p_purchase_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.inventory_writer();
  v_request jsonb := jsonb_build_object(
    'purchase_id', p_purchase_id, 'expected_version', p_expected_version);
  v_replay jsonb;
  v_purchase public.film_purchases%rowtype;
  v_removed integer;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'void_purchase', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  select * into v_purchase from public.film_purchases
  where id = p_purchase_id and owner_user_id = v_user and origin = 'inventory'
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_purchase.voided_at is not null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  if v_purchase.version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;
  if exists (select 1 from public.film_units u
             where u.purchase_id = p_purchase_id and u.status = 'loaded') then
    raise exception 'purchase_in_use' using errcode = 'P1108';
  end if;

  update public.film_purchases set voided_at = now(), version = version + 1
  where id = p_purchase_id;
  update public.film_units set status = 'removed', version = version + 1
  where purchase_id = p_purchase_id and status = 'available';
  get diagnostics v_removed = row_count;

  return app_private.command_record(v_user, p_command_id, 'void_purchase', v_request,
    jsonb_build_object('purchase_id', p_purchase_id, 'removed', v_removed));
end;
$$;

-- Al borrar un rollo, sus costos se quedan con lo que el rollo tenía en ese
-- momento. Durante el borrado de cuenta no hace nada: todo cae por cascada.
create function app_private.costs_freeze_roll()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.borrado_de_cuenta_en_curso() then
    return old;
  end if;
  update public.film_purchases
     set film_stock_id = old.film_stock_id, format = old.format
   where roll_id = old.id and origin = 'roll' and owner_user_id = old.owner_user_id;
  return old;
end;
$$;
revoke all on function app_private.costs_freeze_roll() from public, anon, authenticated;

create trigger costs_freeze_roll before delete on public.rolls
for each row execute function app_private.costs_freeze_roll();

-- Precio del film de un rollo que no salió del inventario. Crea, corrige con
-- versión, o anula si precio, moneda y fecha llegan vacíos.
create function public.film_cost_set(
  p_command_id uuid,
  p_roll_id bigint,
  p_expected_version integer,
  p_unit_price_minor bigint,
  p_currency text,
  p_purchased_on date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.costs_writer();
  v_request jsonb := jsonb_build_object(
    'roll_id', p_roll_id, 'expected_version', p_expected_version,
    'unit_price_minor', p_unit_price_minor, 'currency', p_currency,
    'purchased_on', p_purchased_on);
  v_replay jsonb;
  v_roll public.rolls%rowtype;
  v_purchase public.film_purchases%rowtype;
  v_clear boolean := p_unit_price_minor is null and p_currency is null and p_purchased_on is null;
  v_result jsonb;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'film_cost_set', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  select * into v_roll from public.rolls
  where id = p_roll_id and owner_user_id = v_user
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if exists (select 1 from public.film_units u where u.roll_id = p_roll_id) then
    raise exception 'managed_by_inventory' using errcode = 'P1110';
  end if;
  perform app_private.check_purchase_fields(p_unit_price_minor, p_currency, p_purchased_on);

  select * into v_purchase from public.film_purchases
  where roll_id = p_roll_id and origin = 'roll' and voided_at is null
  for update;
  if (v_purchase.id is null) <> (p_expected_version is null)
     or v_purchase.version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if v_clear and v_purchase.id is null then
    v_result := jsonb_build_object('id', null, 'version', null, 'active', false);
  elsif v_clear then
    update public.film_purchases set voided_at = now(), version = version + 1
    where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', false);
  elsif v_purchase.id is null then
    insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity,
                                       unit_price_minor, currency, purchased_on, origin, roll_id)
    values (v_user, v_roll.film_stock_id, v_roll.format, 1,
            p_unit_price_minor, p_currency, p_purchased_on, 'roll', p_roll_id)
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  else
    update public.film_purchases
       set unit_price_minor = p_unit_price_minor, currency = p_currency,
           purchased_on = p_purchased_on, version = version + 1
     where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  end if;

  return app_private.command_record(v_user, p_command_id, 'film_cost_set', v_request, v_result);
end;
$$;
revoke all on function public.film_cost_set(uuid, bigint, integer, bigint, text, date) from public, anon;
grant execute on function public.film_cost_set(uuid, bigint, integer, bigint, text, date) to authenticated;

create index film_purchases_roll_id_idx on public.film_purchases(roll_id);
