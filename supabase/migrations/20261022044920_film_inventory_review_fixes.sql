-- ANA-173: correcciones de la revisión independiente del inventario.
--
-- 1. Una carga hecha sin conexión se sincroniza días después: la fecha del
--    dispositivo se acepta hasta un año atrás (y un día adelante, por zonas
--    horarias), y la carga guarda el momento real como lo hace la app.
-- 2. Las escrituras de una misma cuenta van una tras otra: dos dispositivos no
--    pueden descuadrar una línea ni anular una compra mientras se carga.
-- 3. Corregir un rollo a la línea de su propia unidad lo reconcilia si se
--    editó por la vía de siempre.

create or replace function app_private.check_local_date(p_today date)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_today is null or p_today > current_date + 1 or p_today < current_date - 365 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
end;
$$;

create or replace function app_private.command_replay(
  p_owner uuid, p_command_id uuid, p_kind text, p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receipt public.inventory_commands%rowtype;
begin
  if p_command_id is null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  -- Dos llegadas simultáneas del mismo comando se ordenan aquí: la segunda
  -- espera a que la primera termine y encuentra su recibo.
  perform pg_advisory_xact_lock(hashtextextended('inventory_cmd:' || p_command_id::text, 0));
  -- Y las escrituras de una misma cuenta, aunque sean comandos distintos.
  perform pg_advisory_xact_lock(hashtextextended('inventory_owner:' || p_owner::text, 0));
  select * into v_receipt from public.inventory_commands where command_id = p_command_id;
  if not found then
    return null;
  end if;
  if v_receipt.owner_user_id is distinct from p_owner
     or v_receipt.kind is distinct from p_kind
     or v_receipt.request_hash is distinct from md5(p_request::text) then
    raise exception 'command_conflict' using errcode = 'P1106';
  end if;
  return v_receipt.result;
end;
$$;

create or replace function public.inventory_swap(
  p_command_id uuid,
  p_roll_id bigint,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.inventory_writer();
  v_request jsonb := jsonb_build_object(
    'roll_id', p_roll_id, 'film_stock_id', p_film_stock_id, 'format', p_format,
    'expiration_date', p_expiration_date, 'declared_fresh', p_declared_fresh);
  v_replay jsonb;
  v_current public.film_units;
  v_next public.film_units;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'swap', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  select * into v_current from public.film_units u
  where u.roll_id = p_roll_id and u.owner_user_id = v_user and u.status = 'loaded'
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if p_format is distinct from v_current.format then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  perform app_private.check_film_line(p_film_stock_id, p_format);

  if app_private.unit_in_line(v_current, p_film_stock_id, p_format, p_expiration_date, p_declared_fresh) then
    v_next := v_current;
  else
    v_next := app_private.next_available_unit(
      v_user, p_film_stock_id, p_format, p_expiration_date, p_declared_fresh);
    if v_next.id is null then
      raise exception 'stock_conflict' using errcode = 'P1104';
    end if;
    update public.film_units
       set status = 'available', roll_id = null, loaded_on = null, version = version + 1
     where id = v_current.id;
    update public.film_units
       set status = 'loaded', roll_id = p_roll_id, loaded_on = v_current.loaded_on, version = version + 1
     where id = v_next.id;
  end if;

  -- El rollo queda igual a su unidad, aunque se haya editado por la vía de
  -- siempre. La condición se calcula con el día en que se cargó, no con hoy.
  update public.rolls
     set film_stock_id = v_next.film_stock_id,
         expiration_date = v_next.expiration_date,
         fresh = not app_private.film_unit_expired(
           v_next.expiration_date, v_next.declared_fresh, v_current.loaded_on)
   where id = p_roll_id
     and owner_user_id = v_user
     and (film_stock_id, expiration_date, fresh) is distinct from (
       v_next.film_stock_id, v_next.expiration_date,
       not app_private.film_unit_expired(v_next.expiration_date, v_next.declared_fresh, v_current.loaded_on));

  return app_private.command_record(v_user, p_command_id, 'swap', v_request,
    jsonb_build_object('roll_id', p_roll_id, 'unit_id', v_next.id));
end;
$$;

-- La carga acepta el momento real en que se hizo (sin conexión puede ser días
-- antes de sincronizar), igual que la inserción directa de la app.
drop function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text);

create function public.inventory_load(
  p_command_id uuid,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean,
  p_today date,
  p_camera_id bigint,
  p_lens_id bigint,
  p_exp_count integer,
  p_push_pull text,
  p_created_at timestamptz default null
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
    'today', p_today, 'camera_id', p_camera_id, 'lens_id', p_lens_id,
    'exp_count', p_exp_count, 'push_pull', p_push_pull, 'created_at', p_created_at);
  v_replay jsonb;
  v_camera_format text;
  v_unit public.film_units;
  v_roll_id bigint;
  v_code text;
  v_attempt integer := 0;
  v_constraint text;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'load', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  perform app_private.check_local_date(p_today);
  -- El momento cae en el mismo día local (±1 por zona horaria) y no en el futuro.
  if p_created_at is not null
     and (p_created_at > now() + interval '1 day'
          or abs((p_created_at at time zone 'UTC')::date - p_today) > 1) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  perform app_private.check_film_line(p_film_stock_id, p_format);
  select c.format into v_camera_format
  from public.cameras c
  where c.id = p_camera_id and c.owner_user_id = v_user;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if app_private.camera_roll_format(v_camera_format) is distinct from p_format then
    raise exception 'incompatible_camera' using errcode = 'P1107';
  end if;
  if p_lens_id is not null and not exists (
    select 1 from public.lenses l where l.id = p_lens_id and l.owner_user_id = v_user
  ) then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  if p_exp_count is null or p_exp_count not between 1 and 100 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  v_unit := app_private.next_available_unit(
    v_user, p_film_stock_id, p_format, p_expiration_date, p_declared_fresh);
  if v_unit.id is null then
    raise exception 'stock_conflict' using errcode = 'P1104';
  end if;

  -- El código se asigna aquí, con candado por cuenta; si una inserción de la
  -- app gana el mismo código, se toma el siguiente.
  perform pg_advisory_xact_lock(hashtextextended('roll_code:' || v_user::text, 0));
  loop
    v_attempt := v_attempt + 1;
    v_code := app_private.next_roll_code(v_user);
    begin
      insert into public.rolls (
        code, client_uuid, owner_user_id, status, film_stock_id, format, exp_count,
        camera_id, lens_id, push_pull, started, created_at, expiration_date, fresh)
      values (
        v_code, p_command_id, v_user, 'In Camera', p_film_stock_id, p_format, p_exp_count,
        p_camera_id, p_lens_id, coalesce(nullif(btrim(p_push_pull), ''), '0'), p_today,
        coalesce(p_created_at, now()), v_unit.expiration_date,
        not app_private.film_unit_expired(v_unit.expiration_date, v_unit.declared_fresh, p_today))
      returning id into v_roll_id;
    exception when unique_violation then
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint = 'rolls_client_uuid_key' then
        raise exception 'command_conflict' using errcode = 'P1106';
      elsif v_constraint is distinct from 'rolls_owner_code_unique' or v_attempt >= 6 then
        raise;
      end if;
    end;
    exit when v_roll_id is not null;
  end loop;

  update public.film_units
     set status = 'loaded', roll_id = v_roll_id, loaded_on = p_today, version = version + 1
   where id = v_unit.id;

  return app_private.command_record(v_user, p_command_id, 'load', v_request,
    jsonb_build_object('roll_id', v_roll_id, 'code', v_code, 'unit_id', v_unit.id));
end;
$$;

revoke all on function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text, timestamptz) from public, anon;
grant execute on function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text, timestamptz) to authenticated;
