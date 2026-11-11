-- ANA-173: cargar un rollo desde el inventario, corregir de qué línea salió y
-- borrar un rollo cargado devolviendo o no su unidad.
--
-- La carga crea el rollo como lo crea hoy la app (inserción con client_uuid) y
-- mueve la unidad en la misma transacción. Los rollos que no vienen del
-- inventario siguen exactamente igual.

-- Misma regla que nextFilmCode de la app: R + mayor número + 1, al menos tres
-- dígitos, sin truncar.
create function app_private.next_roll_code(p_owner uuid)
returns text
language sql
stable
set search_path = ''
as $$
  select 'R' || lpad(s.n::text, greatest(3, length(s.n::text)), '0')
  from (
    select coalesce(max((m[1])::numeric), 0) + 1 as n
    from public.rolls r
    cross join lateral regexp_match(btrim(r.code), '^R-?(\d+)$', 'i') as m
    where r.owner_user_id = p_owner
  ) s
$$;

-- Formato de rollo que acepta una cámara, como edit_film_screen.dart.
create function app_private.camera_roll_format(p_format text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case lower(btrim(p_format))
    when '35' then 35 when '35mm' then 35 when '135' then 35
    when '120' then 120 when '6x4.5' then 120 when 'medium format' then 120 when 'mf' then 120
    when '110' then 110
  end
$$;

-- Primero sale la compra más antigua; las unidades sin compra al final. Una
-- unidad bloqueada por otra carga en curso se salta.
create function app_private.next_available_unit(
  p_owner uuid,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean
)
returns public.film_units
language sql
volatile
set search_path = ''
as $$
  select u.*
  from public.film_units u
  left join public.film_purchases p on p.id = u.purchase_id
  where u.owner_user_id = p_owner
    and u.status = 'available'
    and app_private.unit_in_line(u, p_film_stock_id, p_format, p_expiration_date, p_declared_fresh)
  order by (u.purchase_id is null),
           coalesce(p.purchased_on, (p.created_at at time zone 'UTC')::date),
           p.created_at, u.created_at, u.id
  limit 1
  for update of u skip locked
$$;

revoke all on function app_private.next_roll_code(uuid) from public, anon, authenticated;
revoke all on function app_private.camera_roll_format(text) from public, anon, authenticated;
revoke all on function app_private.next_available_unit(uuid, bigint, integer, jsonb, boolean)
  from public, anon, authenticated;

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
  p_push_pull text
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
    'exp_count', p_exp_count, 'push_pull', p_push_pull);
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
        camera_id, lens_id, push_pull, started, expiration_date, fresh)
      values (
        v_code, p_command_id, v_user, 'In Camera', p_film_stock_id, p_format, p_exp_count,
        p_camera_id, p_lens_id, coalesce(nullif(btrim(p_push_pull), ''), '0'), p_today,
        v_unit.expiration_date,
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

-- Cargó una caducidad (o una película del mismo formato) y en realidad era otra.
create function public.inventory_swap(
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
    return app_private.command_record(v_user, p_command_id, 'swap', v_request,
      jsonb_build_object('roll_id', p_roll_id, 'unit_id', v_current.id));
  end if;

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
  -- La condición se calcula con el día en que se cargó, no con hoy.
  update public.rolls
     set film_stock_id = p_film_stock_id,
         expiration_date = v_next.expiration_date,
         fresh = not app_private.film_unit_expired(
           v_next.expiration_date, v_next.declared_fresh, v_current.loaded_on)
   where id = p_roll_id;

  return app_private.command_record(v_user, p_command_id, 'swap', v_request,
    jsonb_build_object('roll_id', p_roll_id, 'unit_id', v_next.id));
end;
$$;

-- La app pregunta antes de borrar un rollo cargado si la unidad regresa.
create function public.inventory_delete_roll(
  p_command_id uuid,
  p_roll_id bigint,
  p_return_unit boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.inventory_writer();
  v_request jsonb := jsonb_build_object('roll_id', p_roll_id, 'return_unit', p_return_unit);
  v_replay jsonb;
  v_unit public.film_units;
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'delete_roll', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  if not exists (
    select 1 from public.rolls r where r.id = p_roll_id and r.owner_user_id = v_user
  ) then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  select * into v_unit from public.film_units u
  where u.roll_id = p_roll_id and u.owner_user_id = v_user and u.status = 'loaded'
  for update;
  if not found or p_return_unit is null then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  if p_return_unit then
    update public.film_units
       set status = 'available', roll_id = null, loaded_on = null, version = version + 1
     where id = v_unit.id;
  end if;
  -- Sin regreso, el on delete set null deja la unidad usada.
  delete from public.rolls where id = p_roll_id and owner_user_id = v_user;

  return app_private.command_record(v_user, p_command_id, 'delete_roll', v_request,
    jsonb_build_object('roll_id', p_roll_id, 'returned', p_return_unit));
end;
$$;

revoke all on function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text) from public, anon;
revoke all on function public.inventory_swap(uuid, bigint, bigint, integer, jsonb, boolean) from public, anon;
revoke all on function public.inventory_delete_roll(uuid, bigint, boolean) from public, anon;
grant execute on function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text) to authenticated;
grant execute on function public.inventory_swap(uuid, bigint, bigint, integer, jsonb, boolean) to authenticated;
grant execute on function public.inventory_delete_roll(uuid, bigint, boolean) to authenticated;
