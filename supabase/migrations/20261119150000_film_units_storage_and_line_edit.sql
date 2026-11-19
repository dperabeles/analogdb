-- Inventario de film: «refrigerado» y «carga» en cada unidad, y editar una
-- línea completa (Diego, 16-nov).
--
-- · refrigerated: la persona guarda ese film en frío. Un caducado
--   refrigerado casi no muestra la caducidad.
-- · respooled: «carga», film respooleado de otro formato (Verita de lata de
--   cine en carretes de 35 mm), no un producto de fábrica.
--
-- Son datos del archivo de cada persona, no del catálogo. Forman parte de la
-- línea: dos unidades del mismo film, formato y caducidad, una refrigerada y
-- otra no, son líneas distintas. El rollo los copia al cargarse, como ya
-- copia la caducidad y la condición.
--
-- Editar una línea cambia, de todas sus unidades disponibles a la vez, la
-- caducidad, las dos casillas y el film. El film solo cambia si las compras
-- de esas unidades quedan completas en la línea: si una compra tiene un
-- rollo cargado o unidades en otra línea, su film ya se usó y no se reescribe
-- aquí (film_in_use).
--
-- Clientes anteriores llaman sin las casillas: los parámetros nuevos tienen
-- valor por omisión (falso), así que siguen operando sus líneas de siempre.

alter table public.film_units
  add column refrigerated boolean not null default false,
  add column respooled boolean not null default false;

alter table public.rolls
  add column film_refrigerated boolean not null default false,
  add column film_respooled boolean not null default false;

-- ── La definición de línea, con las dos casillas ──────────────────────────

drop function app_private.next_available_unit(uuid, bigint, integer, jsonb, boolean);
drop function app_private.unit_in_line(public.film_units, bigint, integer, jsonb, boolean);

create function app_private.unit_in_line(
  u public.film_units,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean,
  p_refrigerated boolean default false,
  p_respooled boolean default false
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
     and (v_expiration is not null or u.declared_fresh = coalesce(p_declared_fresh, true))
     and u.refrigerated = coalesce(p_refrigerated, false)
     and u.respooled = coalesce(p_respooled, false);
end;
$$;

create function app_private.next_available_unit(
  p_owner uuid,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean,
  p_refrigerated boolean default false,
  p_respooled boolean default false
)
returns public.film_units
language sql
set search_path = ''
as $$
  select u.*
  from public.film_units u
  left join public.film_purchases p on p.id = u.purchase_id
  where u.owner_user_id = p_owner
    and u.status = 'available'
    and app_private.unit_in_line(u, p_film_stock_id, p_format, p_expiration_date,
                                 p_declared_fresh, p_refrigerated, p_respooled)
  order by (u.purchase_id is null),
           coalesce(p.purchased_on, (p.created_at at time zone 'UTC')::date),
           p.created_at, u.created_at, u.id
  limit 1
  for update of u skip locked
$$;

revoke all on function app_private.unit_in_line(public.film_units, bigint, integer, jsonb, boolean, boolean, boolean)
  from public, anon, authenticated;
revoke all on function app_private.next_available_unit(uuid, bigint, integer, jsonb, boolean, boolean, boolean)
  from public, anon, authenticated;

-- Lo que identifica una línea en el registro de comandos. Sin casillas queda
-- igual que antes, así que un reintento de un comando viejo sigue empatando.
create function app_private.line_flags_request(p_refrigerated boolean, p_respooled boolean)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when coalesce(p_refrigerated, false) or coalesce(p_respooled, false)
              then jsonb_build_object('refrigerated', coalesce(p_refrigerated, false),
                                      'respooled', coalesce(p_respooled, false))
              else '{}'::jsonb end
$$;
revoke all on function app_private.line_flags_request(boolean, boolean) from public, anon, authenticated;

-- ── Ajustar el conteo de una línea ────────────────────────────────────────

drop function public.inventory_adjust(uuid, bigint, integer, jsonb, boolean, integer, integer);

create function public.inventory_adjust(
  p_command_id uuid,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean,
  p_expected_available integer,
  p_new_available integer,
  p_refrigerated boolean default false,
  p_respooled boolean default false
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
    'expected_available', p_expected_available, 'new_available', p_new_available)
    || app_private.line_flags_request(p_refrigerated, p_respooled);
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
      and app_private.unit_in_line(u, p_film_stock_id, p_format, v_expiration,
                                   p_declared_fresh, p_refrigerated, p_respooled)
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
        and app_private.unit_in_line(u, p_film_stock_id, p_format, v_expiration,
                                     p_declared_fresh, p_refrigerated, p_respooled)
      order by u.created_at desc, u.id desc
      limit v_count - p_new_available
    );
  elsif p_new_available > v_count then
    -- Unidades encontradas: sin compra, costo desconocido, con las casillas
    -- de su línea.
    insert into public.film_units
      (owner_user_id, purchase_id, film_stock_id, format, expiration_date, declared_fresh,
       refrigerated, respooled)
    select v_user, null, p_film_stock_id, p_format, v_expiration,
           case when v_expiration is null then coalesce(p_declared_fresh, true) else true end,
           coalesce(p_refrigerated, false), coalesce(p_respooled, false)
    from generate_series(1, p_new_available - v_count);
  end if;

  return app_private.command_record(v_user, p_command_id, 'adjust', v_request,
    jsonb_build_object('available', p_new_available));
end;
$$;

-- ── Cargar un rollo desde una línea ───────────────────────────────────────

drop function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text, timestamptz);

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
  p_created_at timestamptz default null,
  p_refrigerated boolean default false,
  p_respooled boolean default false
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
    'exp_count', p_exp_count, 'push_pull', p_push_pull, 'created_at', p_created_at)
    || app_private.line_flags_request(p_refrigerated, p_respooled);
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
  p_film_stock_id := app_private.resolve_film_line(p_film_stock_id, p_format);
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
    v_user, p_film_stock_id, p_format, p_expiration_date, p_declared_fresh,
    p_refrigerated, p_respooled);
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
        camera_id, lens_id, push_pull, started, created_at, expiration_date, fresh,
        film_refrigerated, film_respooled)
      values (
        v_code, p_command_id, v_user, 'In Camera', p_film_stock_id, p_format, p_exp_count,
        p_camera_id, p_lens_id, coalesce(nullif(btrim(p_push_pull), ''), '0'), p_today,
        coalesce(p_created_at, now()), v_unit.expiration_date,
        not app_private.film_unit_expired(v_unit.expiration_date, v_unit.declared_fresh, p_today),
        v_unit.refrigerated, v_unit.respooled)
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

-- ── Cambiar la unidad de un rollo cargado ─────────────────────────────────

drop function public.inventory_swap(uuid, bigint, bigint, integer, jsonb, boolean);

create function public.inventory_swap(
  p_command_id uuid,
  p_roll_id bigint,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean,
  p_refrigerated boolean default false,
  p_respooled boolean default false
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
    'expiration_date', p_expiration_date, 'declared_fresh', p_declared_fresh)
    || app_private.line_flags_request(p_refrigerated, p_respooled);
  v_replay jsonb;
  v_current public.film_units;
  v_next public.film_units;
  v_fresh boolean;
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
  p_film_stock_id := app_private.resolve_film_line(p_film_stock_id, p_format);

  if app_private.unit_in_line(v_current, p_film_stock_id, p_format, p_expiration_date,
                              p_declared_fresh, p_refrigerated, p_respooled) then
    v_next := v_current;
  else
    v_next := app_private.next_available_unit(
      v_user, p_film_stock_id, p_format, p_expiration_date, p_declared_fresh,
      p_refrigerated, p_respooled);
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
  v_fresh := not app_private.film_unit_expired(
    v_next.expiration_date, v_next.declared_fresh, v_current.loaded_on);
  update public.rolls
     set film_stock_id = v_next.film_stock_id,
         expiration_date = v_next.expiration_date,
         fresh = v_fresh,
         film_refrigerated = v_next.refrigerated,
         film_respooled = v_next.respooled
   where id = p_roll_id
     and owner_user_id = v_user
     and (film_stock_id, expiration_date, fresh, film_refrigerated, film_respooled)
         is distinct from (v_next.film_stock_id, v_next.expiration_date, v_fresh,
                           v_next.refrigerated, v_next.respooled);

  return app_private.command_record(v_user, p_command_id, 'swap', v_request,
    jsonb_build_object('roll_id', p_roll_id, 'unit_id', v_next.id));
end;
$$;

-- ── Recibir una compra: cada grupo puede traer sus casillas ───────────────

create or replace function public.inventory_receive(
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

  p_film_stock_id := app_private.resolve_film_line(p_film_stock_id, p_format);
  perform app_private.check_purchase_fields(p_unit_price_minor, p_currency, p_purchased_on);
  if p_groups is null or jsonb_typeof(p_groups) <> 'array'
     or jsonb_array_length(p_groups) not between 1 and 50 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  for v_group in select value from jsonb_array_elements(p_groups) loop
    if jsonb_typeof(v_group) <> 'object'
       or jsonb_typeof(v_group -> 'quantity') is distinct from 'number'
       or coalesce(jsonb_typeof(v_group -> 'declared_fresh'), 'null') not in ('boolean', 'null')
       or coalesce(jsonb_typeof(v_group -> 'refrigerated'), 'null') not in ('boolean', 'null')
       or coalesce(jsonb_typeof(v_group -> 'respooled'), 'null') not in ('boolean', 'null') then
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
    (owner_user_id, purchase_id, film_stock_id, format, expiration_date, declared_fresh,
     refrigerated, respooled)
  select v_user, v_purchase, p_film_stock_id, p_format, g.expiration,
         case when g.expiration is null then g.declared_fresh else true end,
         g.refrigerated, g.respooled
  from (
    select app_private.normalize_expiration(e.value -> 'expiration_date') as expiration,
           coalesce((e.value ->> 'declared_fresh')::boolean, true) as declared_fresh,
           coalesce((e.value ->> 'refrigerated')::boolean, false) as refrigerated,
           coalesce((e.value ->> 'respooled')::boolean, false) as respooled,
           (e.value ->> 'quantity')::integer as quantity
    from jsonb_array_elements(p_groups) e
  ) g
  cross join lateral generate_series(1, g.quantity);

  return app_private.command_record(v_user, p_command_id, 'receive', v_request,
    jsonb_build_object('purchase_id', v_purchase, 'units', v_total));
end;
$$;

-- ── Editar una línea ──────────────────────────────────────────────────────

create function public.inventory_edit_line(
  p_command_id uuid,
  p_film_stock_id bigint,
  p_format integer,
  p_expiration_date jsonb,
  p_declared_fresh boolean,
  p_refrigerated boolean,
  p_respooled boolean,
  p_expected_available integer,
  p_new_film_stock_id bigint,
  p_new_expiration_date jsonb,
  p_new_declared_fresh boolean,
  p_new_refrigerated boolean,
  p_new_respooled boolean
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
    'refrigerated', p_refrigerated, 'respooled', p_respooled,
    'expected_available', p_expected_available,
    'new_film_stock_id', p_new_film_stock_id, 'new_expiration_date', p_new_expiration_date,
    'new_declared_fresh', p_new_declared_fresh, 'new_refrigerated', p_new_refrigerated,
    'new_respooled', p_new_respooled);
  v_replay jsonb;
  v_expiration jsonb;
  v_new_expiration jsonb;
  v_new_film bigint;
  v_ids uuid[];
begin
  v_replay := app_private.command_replay(v_user, p_command_id, 'edit_line', v_request);
  if v_replay is not null then
    return v_replay;
  end if;

  if p_refrigerated is null or p_respooled is null
     or p_new_refrigerated is null or p_new_respooled is null
     or p_expected_available is null or p_expected_available < 1 then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  p_film_stock_id := app_private.resolve_film_line(p_film_stock_id, p_format);
  v_new_film := app_private.resolve_film_line(p_new_film_stock_id, p_format);
  v_expiration := app_private.normalize_expiration(p_expiration_date);
  v_new_expiration := app_private.normalize_expiration(p_new_expiration_date);

  -- Las unidades de la línea, con candado; deben ser las que la persona vio.
  select array_agg(locked.id) into v_ids
  from (
    select u.id from public.film_units u
    where u.owner_user_id = v_user and u.status = 'available'
      and app_private.unit_in_line(u, p_film_stock_id, p_format, v_expiration,
                                   p_declared_fresh, p_refrigerated, p_respooled)
    for update
  ) locked;
  if coalesce(array_length(v_ids, 1), 0) <> p_expected_available then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if v_new_film <> p_film_stock_id then
    -- Una compra con un rollo cargado o con unidades fuera de esta línea ya
    -- usó su film: no se reescribe desde aquí.
    if exists (
      select 1 from public.film_units other
      where other.owner_user_id = v_user
        and other.purchase_id in (
          select u.purchase_id from public.film_units u
          where u.id = any (v_ids) and u.purchase_id is not null)
        and not (other.id = any (v_ids))
    ) then
      raise exception 'film_in_use' using errcode = 'P1112';
    end if;
    update public.film_purchases p
       set film_stock_id = v_new_film, version = p.version + 1
     where p.owner_user_id = v_user
       and p.id in (
         select u.purchase_id from public.film_units u
         where u.id = any (v_ids) and u.purchase_id is not null);
  end if;

  update public.film_units
     set film_stock_id = v_new_film,
         expiration_date = v_new_expiration,
         declared_fresh = case when v_new_expiration is null
                               then coalesce(p_new_declared_fresh, true) else true end,
         refrigerated = p_new_refrigerated,
         respooled = p_new_respooled,
         version = version + 1
   where owner_user_id = v_user and id = any (v_ids);

  return app_private.command_record(v_user, p_command_id, 'edit_line', v_request,
    jsonb_build_object('units', p_expected_available));
end;
$$;

-- ── Lo que se lee: la línea con sus casillas ─────────────────────────────

create or replace view public.film_inventory_lines with (security_invoker = true) as
with available_units as (
  select u.owner_user_id, u.film_stock_id, u.format, u.expiration_date,
         case when u.expiration_date is null then u.declared_fresh end as line_declared_fresh,
         u.refrigerated, u.respooled,
         p.unit_price_minor, p.currency
  from public.film_units u
  left join public.film_purchases p on p.id = u.purchase_id
  where u.status = 'available'
),
per_currency as (
  select owner_user_id, film_stock_id, format, expiration_date, line_declared_fresh,
         refrigerated, respooled, currency,
         count(*)::integer as units,
         min(unit_price_minor) as min_minor,
         max(unit_price_minor) as max_minor,
         round(avg(unit_price_minor))::bigint as avg_minor
  from available_units
  where currency is not null
  group by owner_user_id, film_stock_id, format, expiration_date, line_declared_fresh,
           refrigerated, respooled, currency
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
           and c.refrigerated = l.refrigerated
           and c.respooled = l.respooled
       ), '[]'::jsonb) as prices,
       l.refrigerated, l.respooled
from available_units l
group by l.owner_user_id, l.film_stock_id, l.format, l.expiration_date, l.line_declared_fresh,
         l.refrigerated, l.respooled;

-- La ficha del rollo lee rolls_flat: las dos casillas van al final, como
-- pide create or replace view. El resto es la definición vigente, sin cambios.
create or replace view public.rolls_flat with (security_invoker = true) as
 SELECT r.id,
    r.code AS "#",
    fs.type AS "FILM TYPE",
    r.format AS "FORMAT",
        CASE
            WHEN r.fresh IS NULL THEN NULL::text
            WHEN r.fresh THEN 'FRESH'::text
            ELSE 'EXPIRED'::text
        END AS "EXP/FRESH",
    fs.name AS "FILM STOCK",
    fs.manufacturer AS "MANUFACTURER",
    fs.iso AS "ISO",
    r.exp_count AS "EXP",
        CASE
            WHEN c.id IS NULL THEN r.camera_snapshot ->> 'maker'::text
            ELSE c.maker
        END AS "MAKER",
        CASE
            WHEN c.id IS NULL THEN r.camera_snapshot ->> 'model'::text
            ELSE c.model
        END AS "MODEL NAME",
        CASE
            WHEN c.id IS NULL THEN r.camera_snapshot ->> 'format'::text
            ELSE c.format
        END AS "C. FORMAT",
        CASE
            WHEN c.id IS NULL THEN r.camera_snapshot ->> 'type'::text
            ELSE c.type
        END AS "C. TYPE",
        CASE
            WHEN c.id IS NULL THEN r.camera_snapshot ->> 'mount'::text
            ELSE c.mount
        END AS "C. MOUNT",
    COALESCE(NULLIF(TRIM(BOTH FROM concat_ws(' '::text, l.maker, l.model)), ''::text),
        CASE
            WHEN l.id IS NULL THEN r.lens_snapshot ->> 'display_name'::text
            ELSE NULL::text
        END, r.lens) AS "LENS",
        CASE
            WHEN l.id IS NULL THEN r.lens_snapshot ->> 'mount'::text
            ELSE l.mount
        END AS "LENS MOUNT",
    array_to_string(r.locations, ', '::text) AS "LOCATIONS",
    array_to_string(r.photo_types, ', '::text) AS "PHOTO TYPE",
    array_to_string(r.tags, ', '::text) AS "TAGS",
    r.iso_pushed AS "ISO @",
    to_char(r.started::timestamp with time zone, 'YYYY-MM-DD'::text) AS "STARTED",
    to_char(r.finished::timestamp with time zone, 'YYYY-MM-DD'::text) AS "FINISHED",
    r.exp_taken AS "# EXP",
    r.push_pull AS "PUSH/PULL",
    dl.name AS "DEV",
    sl.name AS "SCAN",
    r.status AS "STATUS",
    r.rating AS "RATING",
    r.notes AS "NOTES",
    r.updated_at,
    COALESCE(re_stats.frame_settings_count, 0::bigint)::integer AS "FRAME SETTINGS",
    r.dev_lab_id AS "DEV LAB ID",
    r.scan_lab_id AS "SCAN LAB ID",
    r.camera_id AS "CAMERA ID",
    r.lens_id AS "LENS ID",
        CASE
            WHEN c.id IS NULL THEN (r.camera_snapshot ->> 'interchangeable'::text)::boolean
            ELSE c.supports_interchangeable_lenses
        END AS "CAMERA INTERCHANGEABLE",
    r.expiration_year AS "EXPIRATION YEAR",
    r.expiration_date::jsonb AS "EXPIRATION DATE",
    r.camera_id IS NULL AND r.camera_snapshot IS NOT NULL AS "CAMERA DELETED",
    r.lens_id IS NULL AND r.lens_snapshot IS NOT NULL AS "LENS DELETED",
    r.film_refrigerated AS "FILM REFRIGERATED",
    r.film_respooled AS "FILM RESPOOLED"
   FROM rolls r
     LEFT JOIN film_stocks fs ON fs.id = r.film_stock_id
     LEFT JOIN cameras c ON c.id = r.camera_id
     LEFT JOIN lenses l ON l.id = r.lens_id
     LEFT JOIN labs dl ON dl.id = r.dev_lab_id
     LEFT JOIN labs sl ON sl.id = r.scan_lab_id
     LEFT JOIN LATERAL ( SELECT count(*) FILTER (WHERE re.lens_source IS NOT NULL OR COALESCE(re.luz_natural, false) OR re.apertura IS NOT NULL OR re.shutter_speed IS NOT NULL OR COALESCE(re.tripie, false) OR COALESCE(re.filtros, false) OR COALESCE(re.flash, false) OR COALESCE(re.luz_natural, false) OR COALESCE(re.multiple_exposures, false) OR re.notes IS NOT NULL) AS frame_settings_count
           FROM roll_exposures re
          WHERE re.roll_id = r.id) re_stats ON true;

-- ── Permisos: solo cuentas con sesión, como el resto de los comandos ──────

revoke all on function public.inventory_adjust(uuid, bigint, integer, jsonb, boolean, integer, integer, boolean, boolean)
  from public, anon;
revoke all on function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text, timestamptz, boolean, boolean)
  from public, anon;
revoke all on function public.inventory_swap(uuid, bigint, bigint, integer, jsonb, boolean, boolean, boolean)
  from public, anon;
revoke all on function public.inventory_edit_line(uuid, bigint, integer, jsonb, boolean, boolean, boolean, integer, bigint, jsonb, boolean, boolean, boolean)
  from public, anon;
grant execute on function public.inventory_adjust(uuid, bigint, integer, jsonb, boolean, integer, integer, boolean, boolean)
  to authenticated;
grant execute on function public.inventory_load(uuid, bigint, integer, jsonb, boolean, date, bigint, bigint, integer, text, timestamptz, boolean, boolean)
  to authenticated;
grant execute on function public.inventory_swap(uuid, bigint, bigint, integer, jsonb, boolean, boolean, boolean)
  to authenticated;
grant execute on function public.inventory_edit_line(uuid, bigint, integer, jsonb, boolean, boolean, boolean, integer, bigint, jsonb, boolean, boolean, boolean)
  to authenticated;
