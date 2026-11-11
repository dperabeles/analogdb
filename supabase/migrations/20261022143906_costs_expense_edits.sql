-- Costos (ANA-184), parte 4: corregir, anular y deshacer cualquier registro de
-- costo por su id, como la lista de Registros de Cifras, aunque su rollo o su
-- equipo ya no exista. Las compras del inventario siguen con sus funciones.
--   source: 'film_roll' (precio del film de un rollo), 'lab' o 'equipment'.

create function public.expense_update(
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
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'expense_update', v_request);
  if v_replay is not null then
    return v_replay;
  end if;
  if p_source is null or p_source not in ('film_roll', 'lab', 'equipment') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  if p_source = 'film_roll' then
    select voided_at, version into v_voided_at, v_version from public.film_purchases
    where id = p_id and owner_user_id = v_user and origin = 'roll' for update;
  elsif p_source = 'lab' then
    select voided_at, version into v_voided_at, v_version from public.lab_charges
    where id = p_id and owner_user_id = v_user for update;
  else
    select voided_at, version into v_voided_at, v_version from public.equipment_purchases
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
       set unit_price_minor = p_amount_minor, currency = p_currency,
           purchased_on = p_paid_on, version = version + 1
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
       set amount_minor = p_amount_minor, currency = p_currency,
           purchased_on = p_paid_on, version = version + 1
     where id = p_id
    returning version into v_version;
  end if;

  return app_private.command_record(v_user, p_command_id, 'expense_update', v_request,
    jsonb_build_object('id', p_id, 'version', v_version, 'active', true));
end;
$$;

create function public.expense_void(
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
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'expense_void', v_request);
  if v_replay is not null then
    return v_replay;
  end if;
  if p_source is null or p_source not in ('film_roll', 'lab', 'equipment') then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  if p_source = 'film_roll' then
    select voided_at, version into v_voided_at, v_version from public.film_purchases
    where id = p_id and owner_user_id = v_user and origin = 'roll' for update;
  elsif p_source = 'lab' then
    select voided_at, version into v_voided_at, v_version from public.lab_charges
    where id = p_id and owner_user_id = v_user for update;
  else
    select voided_at, version into v_voided_at, v_version from public.equipment_purchases
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
    update public.film_purchases set voided_at = now(), version = version + 1
    where id = p_id returning version into v_version;
  elsif p_source = 'lab' then
    update public.lab_charges set voided_at = now(), version = version + 1
    where id = p_id returning version into v_version;
  else
    update public.equipment_purchases set voided_at = now(), version = version + 1
    where id = p_id returning version into v_version;
  end if;

  return app_private.command_record(v_user, p_command_id, 'expense_void', v_request,
    jsonb_build_object('id', p_id, 'version', v_version, 'active', false));
end;
$$;

-- Deshacer una anulación, si mientras tanto nada ocupó su lugar.
create function public.expense_restore(
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
  v_taken boolean := false;
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

  -- Sin rollo o sin equipo ya no hay con quién chocar.
  if p_source = 'film_roll' and v_film.roll_id is not null then
    v_taken := exists (select 1 from public.film_purchases p
                       where p.roll_id = v_film.roll_id and p.origin = 'roll' and p.voided_at is null)
            or exists (select 1 from public.film_units u where u.roll_id = v_film.roll_id);
  elsif p_source = 'lab' and v_lab.roll_id is not null then
    v_taken := exists (select 1 from public.lab_charges c
                       where c.roll_id = v_lab.roll_id and c.voided_at is null
                         and (c.kind = v_lab.kind or c.kind = 'dev_scan' or v_lab.kind = 'dev_scan'));
  elsif p_source = 'equipment' then
    v_taken := exists (select 1 from public.equipment_purchases e
                       where e.voided_at is null
                         and ((v_gear.camera_id is not null and e.camera_id = v_gear.camera_id)
                              or (v_gear.lens_id is not null and e.lens_id = v_gear.lens_id)));
  end if;
  if v_taken then
    raise exception 'already_replaced' using errcode = 'P1111';
  end if;

  if p_source = 'film_roll' then
    update public.film_purchases set voided_at = null, version = version + 1
    where id = p_id returning version into v_version;
  elsif p_source = 'lab' then
    update public.lab_charges set voided_at = null, version = version + 1
    where id = p_id returning version into v_version;
  else
    update public.equipment_purchases set voided_at = null, version = version + 1
    where id = p_id returning version into v_version;
  end if;

  return app_private.command_record(v_user, p_command_id, 'expense_restore', v_request,
    jsonb_build_object('id', p_id, 'version', v_version, 'active', true));
end;
$$;

revoke all on function public.expense_update(uuid, text, uuid, integer, bigint, text, date) from public, anon;
revoke all on function public.expense_void(uuid, text, uuid, integer) from public, anon;
revoke all on function public.expense_restore(uuid, text, uuid, integer) from public, anon;
grant execute on function public.expense_update(uuid, text, uuid, integer, bigint, text, date) to authenticated;
grant execute on function public.expense_void(uuid, text, uuid, integer) to authenticated;
grant execute on function public.expense_restore(uuid, text, uuid, integer) to authenticated;
