-- ANA-173: añadir film al inventario y corregir compras y disponibles.
--
-- Cada función: cuenta habilitada, recibo del comando (un reintento devuelve
-- lo mismo), validación, escritura y recibo, todo en una transacción.

-- Precio y moneda van juntos; la fecha de compra es real y opcional.
create function app_private.check_purchase_fields(
  p_unit_price_minor bigint, p_currency text, p_purchased_on date
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if (p_unit_price_minor is null) <> (p_currency is null)
     or (p_unit_price_minor is not null
         and (p_unit_price_minor < 0 or p_unit_price_minor > 1000000000000))
     or (p_currency is not null and not exists (
           select 1 from public.currencies c where c.code = p_currency and c.active))
     or (p_purchased_on is not null
         and (p_purchased_on > current_date + 1 or p_purchased_on < date '1900-01-01')) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
end;
$$;

-- La película existe y el formato es un rollo físico del inventario.
create function app_private.check_film_line(p_film_stock_id bigint, p_format integer)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_format is null or p_format not in (35, 120, 110)
     or not exists (select 1 from public.film_stocks s where s.id = p_film_stock_id) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
end;
$$;

revoke all on function app_private.check_purchase_fields(bigint, text, date) from public, anon, authenticated;
revoke all on function app_private.check_film_line(bigint, integer) from public, anon, authenticated;

create function public.inventory_receive(
  p_command_id uuid,
  p_film_stock_id bigint,
  p_format integer,
  p_unit_price_minor bigint,
  p_currency text,
  p_purchased_on date,
  p_groups jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.inventory_writer();
  v_request jsonb := jsonb_build_object(
    'film_stock_id', p_film_stock_id, 'format', p_format,
    'unit_price_minor', p_unit_price_minor, 'currency', p_currency,
    'purchased_on', p_purchased_on, 'groups', p_groups);
  v_replay jsonb;
  v_group jsonb;
  v_quantity numeric;
  v_total integer := 0;
  v_purchase uuid;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'receive', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  perform app_private.check_film_line(p_film_stock_id, p_format);
  perform app_private.check_purchase_fields(p_unit_price_minor, p_currency, p_purchased_on);
  if p_groups is null or jsonb_typeof(p_groups) <> 'array'
     or jsonb_array_length(p_groups) not between 1 and 50 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  for v_group in select value from jsonb_array_elements(p_groups) loop
    if jsonb_typeof(v_group) <> 'object'
       or jsonb_typeof(v_group -> 'quantity') is distinct from 'number'
       or coalesce(jsonb_typeof(v_group -> 'declared_fresh'), 'null') not in ('boolean', 'null') then
      raise exception 'invalid_input' using errcode = 'P1103';
    end if;
    v_quantity := (v_group ->> 'quantity')::numeric;
    if v_quantity <> trunc(v_quantity) or v_quantity not between 1 and 9999 then
      raise exception 'invalid_input' using errcode = 'P1103';
    end if;
    v_total := v_total + v_quantity::integer;
    perform app_private.normalize_expiration(v_group -> 'expiration_date');
  end loop;
  if v_total > 9999 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  insert into public.film_purchases
    (owner_user_id, film_stock_id, format, quantity, unit_price_minor, currency, purchased_on)
  values (v_user, p_film_stock_id, p_format, v_total, p_unit_price_minor, p_currency, p_purchased_on)
  returning id into v_purchase;

  -- Con fecha manda la fecha; la declaración solo se guarda sin fecha.
  insert into public.film_units
    (owner_user_id, purchase_id, film_stock_id, format, expiration_date, declared_fresh)
  select v_user, v_purchase, p_film_stock_id, p_format, g.expiration,
         case when g.expiration is null then g.declared_fresh else true end
  from (
    select app_private.normalize_expiration(e.value -> 'expiration_date') as expiration,
           coalesce((e.value ->> 'declared_fresh')::boolean, true) as declared_fresh,
           (e.value ->> 'quantity')::integer as quantity
    from jsonb_array_elements(p_groups) e
  ) g
  cross join lateral generate_series(1, g.quantity);

  return app_private.command_record(v_user, p_command_id, 'receive', v_request,
    jsonb_build_object('purchase_id', v_purchase, 'units', v_total));
end;
$$;

-- Corrección física de una línea: nunca toca compras, importes ni cargadas.
create function public.inventory_adjust(
  p_command_id uuid,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean,
  p_expected_available integer,
  p_new_available integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.inventory_writer();
  v_request jsonb := jsonb_build_object(
    'film_stock_id', p_film_stock_id, 'format', p_format,
    'expiration_date', p_expiration_date, 'declared_fresh', p_declared_fresh,
    'expected_available', p_expected_available, 'new_available', p_new_available);
  v_replay jsonb;
  v_expiration jsonb;
  v_count integer;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'adjust', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  perform app_private.check_film_line(p_film_stock_id, p_format);
  v_expiration := app_private.normalize_expiration(p_expiration_date);
  if p_expected_available is null or p_expected_available < 0
     or p_new_available is null or p_new_available not between 0 and 9999 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  select count(*) into v_count
  from (
    select u.id from public.film_units u
    where u.owner_user_id = v_user and u.status = 'available'
      and app_private.unit_in_line(u, p_film_stock_id, p_format, v_expiration, p_declared_fresh)
    for update
  ) locked;
  if v_count <> p_expected_available then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if p_new_available < v_count then
    update public.film_units set status = 'removed', version = version + 1
    where id in (
      select u.id from public.film_units u
      where u.owner_user_id = v_user and u.status = 'available'
        and app_private.unit_in_line(u, p_film_stock_id, p_format, v_expiration, p_declared_fresh)
      order by u.created_at desc, u.id desc
      limit v_count - p_new_available
    );
  elsif p_new_available > v_count then
    -- Unidades encontradas: sin compra, costo desconocido.
    insert into public.film_units
      (owner_user_id, purchase_id, film_stock_id, format, expiration_date, declared_fresh)
    select v_user, null, p_film_stock_id, p_format, v_expiration,
           case when v_expiration is null then coalesce(p_declared_fresh, true) else true end
    from generate_series(1, p_new_available - v_count);
  end if;

  return app_private.command_record(v_user, p_command_id, 'adjust', v_request,
    jsonb_build_object('available', p_new_available));
end;
$$;

-- Corregir una compra corrige el costo de todos los rollos que salieron de ella.
create function public.inventory_update_purchase(
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
  where id = p_purchase_id and owner_user_id = v_user
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

-- Anular solo mientras ninguna de sus unidades se haya cargado.
create function public.inventory_void_purchase(
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
  where id = p_purchase_id and owner_user_id = v_user
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

revoke all on function public.inventory_receive(uuid, bigint, integer, bigint, text, date, jsonb) from public, anon;
revoke all on function public.inventory_adjust(uuid, bigint, integer, jsonb, boolean, integer, integer) from public, anon;
revoke all on function public.inventory_update_purchase(uuid, uuid, integer, bigint, text, date) from public, anon;
revoke all on function public.inventory_void_purchase(uuid, uuid, integer) from public, anon;
grant execute on function public.inventory_receive(uuid, bigint, integer, bigint, text, date, jsonb) to authenticated;
grant execute on function public.inventory_adjust(uuid, bigint, integer, jsonb, boolean, integer, integer) to authenticated;
grant execute on function public.inventory_update_purchase(uuid, uuid, integer, bigint, text, date) to authenticated;
grant execute on function public.inventory_void_purchase(uuid, uuid, integer) to authenticated;
