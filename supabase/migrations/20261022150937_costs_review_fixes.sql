-- Costos (ANA-184): correcciones de la revisión independiente (22-oct).
-- 1. Cada gasto guarda para siempre de qué rollo o pieza salió (source_*, sin
--    llave foránea). Así, deshacer una anulación con el rollo o el equipo ya
--    borrado choca con el registro que la reemplazó y no cuenta dos veces.
-- 2. Las compras de un mismo rollo o pieza comparten una sola secuencia de
--    versiones: una compra nueva nunca repite la versión de una anterior, y
--    un dispositivo con una versión vieja no puede pisarla.

alter table public.film_purchases add column source_roll_id bigint;
update public.film_purchases set source_roll_id = roll_id where origin = 'roll';
alter table public.film_purchases
  add constraint film_purchases_roll_source check ((origin = 'roll') = (source_roll_id is not null));

alter table public.lab_charges add column source_roll_id bigint;
update public.lab_charges set source_roll_id = roll_id;
alter table public.lab_charges alter column source_roll_id set not null;

alter table public.equipment_purchases add column source_item_id bigint;
update public.equipment_purchases set source_item_id = coalesce(camera_id, lens_id);
alter table public.equipment_purchases alter column source_item_id set not null;

-- El origen se toma del rollo o la pieza al crear el registro y no cambia.
create function app_private.costs_set_source()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_table_name = 'film_purchases' then
    if new.origin = 'roll' then
      new.source_roll_id := coalesce(new.source_roll_id, new.roll_id);
    end if;
  elsif tg_table_name = 'lab_charges' then
    new.source_roll_id := coalesce(new.source_roll_id, new.roll_id);
  else
    new.source_item_id := coalesce(new.source_item_id, new.camera_id, new.lens_id);
  end if;
  return new;
end;
$$;
revoke all on function app_private.costs_set_source() from public, anon, authenticated;

create trigger costs_set_source before insert on public.film_purchases
for each row execute function app_private.costs_set_source();
create trigger costs_set_source before insert on public.lab_charges
for each row execute function app_private.costs_set_source();
create trigger costs_set_source before insert on public.equipment_purchases
for each row execute function app_private.costs_set_source();

-- Lo activo es único por origen, exista o no el rollo o la pieza.
drop index public.film_purchases_active_roll_uidx;
create unique index film_purchases_active_roll_uidx on public.film_purchases(source_roll_id)
  where origin = 'roll' and voided_at is null;
drop index public.lab_charges_active_kind_uidx;
create unique index lab_charges_active_kind_uidx on public.lab_charges(source_roll_id, kind)
  where voided_at is null;
drop index public.equipment_purchases_active_camera_uidx;
drop index public.equipment_purchases_active_lens_uidx;
create unique index equipment_purchases_active_item_uidx on public.equipment_purchases(kind, source_item_id)
  where voided_at is null;
-- Para calcular la siguiente versión de un origen.
create index film_purchases_source_roll_id_idx on public.film_purchases(source_roll_id)
  where source_roll_id is not null;
create index equipment_purchases_source_item_idx on public.equipment_purchases(kind, source_item_id);

create function app_private.next_roll_purchase_version(p_roll_id bigint)
returns integer
language sql
stable
set search_path = ''
as $$
  select coalesce(max(version), 0) + 1 from public.film_purchases
  where origin = 'roll' and source_roll_id = p_roll_id
$$;
create function app_private.next_equipment_version(p_kind text, p_item_id bigint)
returns integer
language sql
stable
set search_path = ''
as $$
  select coalesce(max(version), 0) + 1 from public.equipment_purchases
  where kind = p_kind and source_item_id = p_item_id
$$;
revoke all on function app_private.next_roll_purchase_version(bigint) from public, anon, authenticated;
revoke all on function app_private.next_equipment_version(text, bigint) from public, anon, authenticated;

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
    values (v_user, v_roll.film_stock_id, v_roll.format, 1,
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

create or replace function public.equipment_cost_set(
  p_command_id uuid,
  p_kind text,
  p_item_id bigint,
  p_expected_version integer,
  p_amount_minor bigint,
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
    'kind', p_kind, 'item_id', p_item_id, 'expected_version', p_expected_version,
    'amount_minor', p_amount_minor, 'currency', p_currency, 'purchased_on', p_purchased_on);
  v_replay jsonb;
  v_purchase public.equipment_purchases%rowtype;
  v_clear boolean := p_amount_minor is null and p_currency is null and p_purchased_on is null;
  v_result jsonb;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'equipment_cost_set', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  if p_kind is null or p_kind not in ('camera', 'lens') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  if p_kind = 'camera' then
    perform 1 from public.cameras where id = p_item_id and owner_user_id = v_user for update;
  else
    perform 1 from public.lenses where id = p_item_id and owner_user_id = v_user for update;
  end if;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  perform app_private.check_purchase_fields(p_amount_minor, p_currency, p_purchased_on);

  select * into v_purchase from public.equipment_purchases
  where voided_at is null and kind = p_kind and source_item_id = p_item_id
  for update;
  if (v_purchase.id is null) <> (p_expected_version is null)
     or v_purchase.version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if v_clear and v_purchase.id is null then
    v_result := jsonb_build_object('id', null, 'version', null, 'active', false);
  elsif v_clear then
    update public.equipment_purchases
       set voided_at = now(), version = app_private.next_equipment_version(p_kind, p_item_id)
     where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', false);
  elsif v_purchase.id is null then
    insert into public.equipment_purchases (owner_user_id, kind, camera_id, lens_id, source_item_id,
                                            amount_minor, currency, purchased_on, version)
    values (v_user, p_kind,
            case when p_kind = 'camera' then p_item_id end,
            case when p_kind = 'lens' then p_item_id end,
            p_item_id, p_amount_minor, p_currency, p_purchased_on,
            app_private.next_equipment_version(p_kind, p_item_id))
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  else
    update public.equipment_purchases
       set amount_minor = p_amount_minor, currency = p_currency, purchased_on = p_purchased_on,
           version = app_private.next_equipment_version(p_kind, p_item_id)
     where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  end if;

  return app_private.command_record(v_user, p_command_id, 'equipment_cost_set', v_request, v_result);
end;
$$;

create or replace function public.expense_update(
  p_command_id uuid,
  p_source text,
  p_id uuid,
  p_expected_version integer,
  p_amount_minor bigint,
  p_currency text,
  p_paid_on date
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.costs_writer();
  v_request jsonb := jsonb_build_object(
    'source', p_source, 'id', p_id, 'expected_version', p_expected_version,
    'amount_minor', p_amount_minor, 'currency', p_currency, 'paid_on', p_paid_on);
  v_replay jsonb;
  v_voided_at timestamptz;
  v_version integer;
  v_kind text;
  v_origin bigint;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'expense_update', v_request);
  if v_replay is not null then
    return v_replay;
  end if;
  if p_source is null or p_source not in ('film_roll', 'lab', 'equipment') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  if p_source = 'film_roll' then
    select voided_at, version, source_roll_id into v_voided_at, v_version, v_origin
    from public.film_purchases
    where id = p_id and owner_user_id = v_user and origin = 'roll' for update;
  elsif p_source = 'lab' then
    select voided_at, version into v_voided_at, v_version from public.lab_charges
    where id = p_id and owner_user_id = v_user for update;
  else
    select voided_at, version, kind, source_item_id into v_voided_at, v_version, v_kind, v_origin
    from public.equipment_purchases
    where id = p_id and owner_user_id = v_user for update;
  end if;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  -- Corregir no anula: quitar todo es expense_void. Un cargo de lab siempre
  -- lleva importe.
  if v_voided_at is not null
     or (p_amount_minor is null and p_currency is null and p_paid_on is null)
     or (p_source = 'lab' and p_amount_minor is null) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  perform app_private.check_purchase_fields(p_amount_minor, p_currency, p_paid_on);
  if v_version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if p_source = 'film_roll' then
    update public.film_purchases
       set unit_price_minor = p_amount_minor, currency = p_currency, purchased_on = p_paid_on,
           version = app_private.next_roll_purchase_version(v_origin)
     where id = p_id
    returning version into v_version;
  elsif p_source = 'lab' then
    update public.lab_charges
       set amount_minor = p_amount_minor, currency = p_currency,
           charged_on = p_paid_on, version = version + 1
     where id = p_id
    returning version into v_version;
  else
    update public.equipment_purchases
       set amount_minor = p_amount_minor, currency = p_currency, purchased_on = p_paid_on,
           version = app_private.next_equipment_version(v_kind, v_origin)
     where id = p_id
    returning version into v_version;
  end if;

  return app_private.command_record(v_user, p_command_id, 'expense_update', v_request,
    jsonb_build_object('id', p_id, 'version', v_version, 'active', true));
end;
$$;

create or replace function public.expense_void(
  p_command_id uuid,
  p_source text,
  p_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.costs_writer();
  v_request jsonb := jsonb_build_object(
    'source', p_source, 'id', p_id, 'expected_version', p_expected_version);
  v_replay jsonb;
  v_voided_at timestamptz;
  v_version integer;
  v_kind text;
  v_origin bigint;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'expense_void', v_request);
  if v_replay is not null then
    return v_replay;
  end if;
  if p_source is null or p_source not in ('film_roll', 'lab', 'equipment') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  if p_source = 'film_roll' then
    select voided_at, version, source_roll_id into v_voided_at, v_version, v_origin
    from public.film_purchases
    where id = p_id and owner_user_id = v_user and origin = 'roll' for update;
  elsif p_source = 'lab' then
    select voided_at, version into v_voided_at, v_version from public.lab_charges
    where id = p_id and owner_user_id = v_user for update;
  else
    select voided_at, version, kind, source_item_id into v_voided_at, v_version, v_kind, v_origin
    from public.equipment_purchases
    where id = p_id and owner_user_id = v_user for update;
  end if;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_voided_at is not null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  if v_version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if p_source = 'film_roll' then
    update public.film_purchases
       set voided_at = now(), version = app_private.next_roll_purchase_version(v_origin)
     where id = p_id returning version into v_version;
  elsif p_source = 'lab' then
    update public.lab_charges set voided_at = now(), version = version + 1
    where id = p_id returning version into v_version;
  else
    update public.equipment_purchases
       set voided_at = now(), version = app_private.next_equipment_version(v_kind, v_origin)
     where id = p_id returning version into v_version;
  end if;

  return app_private.command_record(v_user, p_command_id, 'expense_void', v_request,
    jsonb_build_object('id', p_id, 'version', v_version, 'active', false));
end;
$$;

-- Deshacer una anulación, si mientras tanto nada ocupó su lugar: se compara
-- por el rollo o la pieza de origen, aunque ya se hayan borrado.
create or replace function public.expense_restore(
  p_command_id uuid,
  p_source text,
  p_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.costs_writer();
  v_request jsonb := jsonb_build_object(
    'source', p_source, 'id', p_id, 'expected_version', p_expected_version);
  v_replay jsonb;
  v_film public.film_purchases%rowtype;
  v_lab public.lab_charges%rowtype;
  v_gear public.equipment_purchases%rowtype;
  v_voided_at timestamptz;
  v_version integer;
  v_taken boolean;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'expense_restore', v_request);
  if v_replay is not null then
    return v_replay;
  end if;
  if p_source is null or p_source not in ('film_roll', 'lab', 'equipment') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  if p_source = 'film_roll' then
    select * into v_film from public.film_purchases
    where id = p_id and owner_user_id = v_user and origin = 'roll' for update;
    v_voided_at := v_film.voided_at;
    v_version := v_film.version;
  elsif p_source = 'lab' then
    select * into v_lab from public.lab_charges
    where id = p_id and owner_user_id = v_user for update;
    v_voided_at := v_lab.voided_at;
    v_version := v_lab.version;
  else
    select * into v_gear from public.equipment_purchases
    where id = p_id and owner_user_id = v_user for update;
    v_voided_at := v_gear.voided_at;
    v_version := v_gear.version;
  end if;
  if v_version is null then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if v_voided_at is null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  if v_version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if p_source = 'film_roll' then
    v_taken := exists (select 1 from public.film_purchases p
                       where p.origin = 'roll' and p.source_roll_id = v_film.source_roll_id
                         and p.voided_at is null)
            or exists (select 1 from public.film_units u where u.roll_id = v_film.source_roll_id);
  elsif p_source = 'lab' then
    v_taken := exists (select 1 from public.lab_charges c
                       where c.source_roll_id = v_lab.source_roll_id and c.voided_at is null
                         and (c.kind = v_lab.kind or c.kind = 'dev_scan' or v_lab.kind = 'dev_scan'));
  else
    v_taken := exists (select 1 from public.equipment_purchases e
                       where e.kind = v_gear.kind and e.source_item_id = v_gear.source_item_id
                         and e.voided_at is null);
  end if;
  if v_taken then
    raise exception 'already_replaced' using errcode = 'P1111';
  end if;

  if p_source = 'film_roll' then
    update public.film_purchases
       set voided_at = null, version = app_private.next_roll_purchase_version(v_film.source_roll_id)
     where id = p_id returning version into v_version;
  elsif p_source = 'lab' then
    update public.lab_charges set voided_at = null, version = version + 1
    where id = p_id returning version into v_version;
  else
    update public.equipment_purchases
       set voided_at = null, version = app_private.next_equipment_version(v_gear.kind, v_gear.source_item_id)
     where id = p_id returning version into v_version;
  end if;

  return app_private.command_record(v_user, p_command_id, 'expense_restore', v_request,
    jsonb_build_object('id', p_id, 'version', v_version, 'active', true));
end;
$$;
