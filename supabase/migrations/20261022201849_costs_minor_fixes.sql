-- Costos (ANA-184): los cuatro menores de la revisión independiente (22-oct).
-- 1. Cifras trae el código del rollo, también de rollos ya borrados: las
--    compras 'roll' lo guardan al borrar el rollo, como los cargos de lab.
-- 2. La compra creada desde la Ficha ya no copia película y formato del
--    rollo: mientras existe se leen de él, y se guardan al borrarlo.
-- 3. Congelar un gasto al borrar su rollo o su equipo sube su versión.
-- 4. Una entrada de expected que no es {id, version} es invalid_input.

alter table public.film_purchases add column roll_code text;

create or replace function app_private.costs_freeze_roll()
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
     set film_stock_id = old.film_stock_id, format = old.format, roll_code = old.code,
         version = version + 1
   where roll_id = old.id and origin = 'roll' and owner_user_id = old.owner_user_id;
  update public.lab_charges
     set lab_id = app_private.charge_lab(kind, old.dev_lab_id, old.scan_lab_id), roll_code = old.code,
         version = version + 1
   where roll_id = old.id and owner_user_id = old.owner_user_id;
  return old;
end;
$$;

create or replace function app_private.costs_freeze_equipment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.borrado_de_cuenta_en_curso() then
    return old;
  end if;
  if tg_table_name = 'cameras' then
    update public.equipment_purchases
       set label = btrim(coalesce(old.maker, '') || ' ' || coalesce(old.model, '')), version = version + 1
     where camera_id = old.id and owner_user_id = old.owner_user_id;
  else
    update public.equipment_purchases
       set label = btrim(coalesce(old.maker, '') || ' ' || coalesce(old.model, '')), version = version + 1
     where lens_id = old.id and owner_user_id = old.owner_user_id;
  end if;
  return old;
end;
$$;

create or replace view public.expense_origins with (security_invoker = true) as
select case p.origin when 'roll' then 'film_roll' else 'film_purchase' end as source,
       p.id, p.version, p.owner_user_id,
       'film'::text as category,
       p.unit_price_minor * p.quantity as amount_minor,
       p.currency::text as currency,
       p.purchased_on as paid_on,
       p.quantity,
       p.unit_price_minor,
       case when r.id is not null then r.film_stock_id else p.film_stock_id end as film_stock_id,
       case when r.id is not null then r.format else p.format end as format,
       p.roll_id,
       null::bigint as lab_id,
       null::bigint as camera_id,
       null::bigint as lens_id,
       nullif(btrim(coalesce(fs.manufacturer, '') || ' ' || coalesce(fs.name, '')), '') as label,
       case when r.id is not null then r.code else p.roll_code end as roll_code
from public.film_purchases p
left join public.rolls r on r.id = p.roll_id and p.origin = 'roll'
left join public.film_stocks fs
  on fs.id = case when r.id is not null then r.film_stock_id else p.film_stock_id end
where p.voided_at is null and p.unit_price_minor is not null
union all
select 'lab', c.id, c.version, c.owner_user_id,
       c.kind, c.amount_minor, c.currency::text, c.charged_on,
       null::integer, null::bigint, null::bigint, null::integer,
       c.roll_id,
       coalesce(l.merged_into_id, k.lab_id),
       null::bigint, null::bigint,
       coalesce(lm.name, l.name),
       coalesce(r.code, c.roll_code)
from public.lab_charges c
left join public.rolls r on r.id = c.roll_id
cross join lateral (
  select case when r.id is null then c.lab_id
              when c.kind = 'scan' then r.scan_lab_id
              when c.kind = 'dev' then r.dev_lab_id
              else coalesce(r.dev_lab_id, r.scan_lab_id)
         end as lab_id
) k
left join public.labs l on l.id = k.lab_id
left join public.labs lm on lm.id = l.merged_into_id
where c.voided_at is null
union all
select 'equipment', e.id, e.version, e.owner_user_id,
       e.kind, e.amount_minor, e.currency::text, e.purchased_on,
       null::integer, null::bigint, null::bigint, null::integer,
       null::bigint, null::bigint,
       e.camera_id, e.lens_id,
       coalesce(nullif(btrim(coalesce(cam.maker, ln.maker, '') || ' ' || coalesce(cam.model, ln.model, '')), ''),
                e.label),
       null::text
from public.equipment_purchases e
left join public.cameras cam on cam.id = e.camera_id
left join public.lenses ln on ln.id = e.lens_id
where e.voided_at is null and e.amount_minor is not null;

create or replace function public.film_cost_set(
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
  where source_roll_id = p_roll_id and origin = 'roll' and voided_at is null
  for update;
  if (v_purchase.id is null) <> (p_expected_version is null)
     or v_purchase.version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if v_clear and v_purchase.id is null then
    v_result := jsonb_build_object('id', null, 'version', null, 'active', false);
  elsif v_clear then
    update public.film_purchases
       set voided_at = now(), version = app_private.next_roll_purchase_version(p_roll_id)
     where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', false);
  elsif v_purchase.id is null then
    insert into public.film_purchases (owner_user_id, film_stock_id, format, quantity,
                                       unit_price_minor, currency, purchased_on, origin, roll_id,
                                       source_roll_id, version)
    values (v_user, null, null, 1,
            p_unit_price_minor, p_currency, p_purchased_on, 'roll', p_roll_id,
            p_roll_id, app_private.next_roll_purchase_version(p_roll_id))
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  else
    update public.film_purchases
       set unit_price_minor = p_unit_price_minor, currency = p_currency,
           purchased_on = p_purchased_on, version = app_private.next_roll_purchase_version(p_roll_id)
     where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  end if;

  return app_private.command_record(v_user, p_command_id, 'film_cost_set', v_request, v_result);
end;
$$;

create or replace function public.lab_costs_save(
  p_command_id uuid,
  p_roll_id bigint,
  p_expected jsonb,
  p_charges jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.costs_writer();
  v_request jsonb := jsonb_build_object(
    'roll_id', p_roll_id, 'expected', p_expected, 'charges', p_charges);
  v_replay jsonb;
  v_item jsonb;
  v_kinds text[] := '{}';
  v_kind text;
  v_amount bigint;
  v_date date;
  v_wanted jsonb := '{}';
  v_expected jsonb;
  v_current jsonb;
  v_row public.lab_charges%rowtype;
  v_voided jsonb := '[]';
  v_result jsonb;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'lab_costs_save', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  perform 1 from public.rolls where id = p_roll_id and owner_user_id = v_user for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;

  if jsonb_typeof(p_charges) is distinct from 'array'
     or jsonb_typeof(p_expected) is distinct from 'array' then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  -- Cada cargo pedido: tipo conocido, importe entero, moneda activa y fecha
  -- real en formato AAAA-MM-DD. Cualquier otra cosa es invalid_input.
  for v_item in select e from jsonb_array_elements(p_charges) e loop
    if jsonb_typeof(v_item) is distinct from 'object'
       or v_item ->> 'kind' is null
       or v_item ->> 'kind' not in ('dev_scan', 'dev', 'scan')
       or jsonb_typeof(v_item -> 'amount_minor') is distinct from 'number'
       or v_item ->> 'amount_minor' !~ '^[0-9]{1,13}$'
       or jsonb_typeof(v_item -> 'currency') is distinct from 'string'
       or coalesce(jsonb_typeof(v_item -> 'charged_on'), 'null') not in ('null', 'string')
       or (jsonb_typeof(v_item -> 'charged_on') = 'string'
           and v_item ->> 'charged_on' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') then
      raise exception 'invalid_input' using errcode = 'P1103';
    end if;
    v_kind := v_item ->> 'kind';
    v_amount := (v_item ->> 'amount_minor')::bigint;
    begin
      v_date := (v_item ->> 'charged_on')::date;
    exception when others then
      raise exception 'invalid_input' using errcode = 'P1103';
    end;
    perform app_private.check_purchase_fields(v_amount, v_item ->> 'currency', v_date);
    if v_kind = any (v_kinds) then
      raise exception 'invalid_input' using errcode = 'P1103';
    end if;
    v_kinds := v_kinds || v_kind;
    v_wanted := v_wanted || jsonb_build_object(v_kind, jsonb_build_object(
      'amount_minor', v_amount, 'currency', v_item ->> 'currency', 'charged_on', v_date));
  end loop;
  if 'dev_scan' = any (v_kinds) and cardinality(v_kinds) > 1 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  -- Lo que la app tenía a la vista debe ser exactamente lo activo ahora: una
  -- lista de {id, version}; cualquier otra forma es invalid_input.
  if exists (select 1 from jsonb_array_elements(p_expected) e
             where jsonb_typeof(e) is distinct from 'object'
                or jsonb_typeof(e -> 'id') is distinct from 'string'
                or jsonb_typeof(e -> 'version') is distinct from 'number') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  begin
    select coalesce(jsonb_agg(jsonb_build_object('id', (e ->> 'id')::uuid, 'version', (e ->> 'version')::integer)
                              order by (e ->> 'id')::uuid), '[]')
      into v_expected
      from jsonb_array_elements(p_expected) e;
  exception when others then
    raise exception 'invalid_input' using errcode = 'P1103';
  end;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'version', c.version) order by c.id), '[]')
    into v_current
    from (select id, version from public.lab_charges
          where roll_id = p_roll_id and voided_at is null
          for update) c;
  if v_expected is distinct from v_current then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  foreach v_kind in array array['dev_scan', 'dev', 'scan'] loop
    select * into v_row from public.lab_charges
    where roll_id = p_roll_id and kind = v_kind and voided_at is null;
    if v_row.id is not null and not v_wanted ? v_kind then
      update public.lab_charges set voided_at = now(), version = version + 1
      where id = v_row.id
      returning * into v_row;
      v_voided := v_voided || jsonb_build_array(jsonb_build_object(
        'id', v_row.id, 'kind', v_row.kind, 'version', v_row.version));
    elsif v_row.id is not null then
      update public.lab_charges
         set amount_minor = (v_wanted -> v_kind ->> 'amount_minor')::bigint,
             currency = v_wanted -> v_kind ->> 'currency',
             charged_on = (v_wanted -> v_kind ->> 'charged_on')::date,
             version = version + 1
       where id = v_row.id
         and (amount_minor, currency::text, charged_on) is distinct from
             ((v_wanted -> v_kind ->> 'amount_minor')::bigint, v_wanted -> v_kind ->> 'currency',
              (v_wanted -> v_kind ->> 'charged_on')::date);
    elsif v_wanted ? v_kind then
      insert into public.lab_charges (owner_user_id, roll_id, kind, amount_minor, currency, charged_on)
      values (v_user, p_roll_id, v_kind, (v_wanted -> v_kind ->> 'amount_minor')::bigint,
              v_wanted -> v_kind ->> 'currency', (v_wanted -> v_kind ->> 'charged_on')::date);
    end if;
  end loop;

  select jsonb_build_object(
           'charges', coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'version', c.version)
                                order by array_position(array['dev_scan', 'dev', 'scan'], c.kind)), '[]'),
           'voided', v_voided)
    into v_result
    from public.lab_charges c
   where c.roll_id = p_roll_id and c.voided_at is null;

  return app_private.command_record(v_user, p_command_id, 'lab_costs_save', v_request, v_result);
end;
$$;
