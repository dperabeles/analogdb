-- Costos (ANA-184), parte 2: cargos de laboratorio por rollo y los costos de
-- cada rollo para la Ficha. Un cargo es Rev + Scan, Revelado o Escaneado; el
-- combinado y los separados nunca están activos a la vez.

create table public.lab_charges (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  roll_id bigint references public.rolls(id) on delete set null,
  kind text not null check (kind in ('dev_scan', 'dev', 'scan')),
  amount_minor bigint not null check (amount_minor between 0 and 1000000000000),
  currency char(3) not null references public.currencies(code),
  charged_on date,
  -- Solo se llenan al borrar el rollo: mientras existe, manda el rollo.
  lab_id bigint references public.labs(id) on delete set null,
  roll_code text,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1
);
create index lab_charges_owner_user_id_idx on public.lab_charges(owner_user_id);
create index lab_charges_roll_id_idx on public.lab_charges(roll_id);
create index lab_charges_lab_id_idx on public.lab_charges(lab_id);
create index lab_charges_currency_idx on public.lab_charges(currency);
create unique index lab_charges_active_kind_uidx on public.lab_charges(roll_id, kind)
  where roll_id is not null and voided_at is null;

create trigger lab_charges_touch before update on public.lab_charges
for each row execute function public.touch_updated_at();
create trigger zz_archivar_borrado before delete on public.lab_charges
for each row execute function public.archivar_fila_borrada();
create trigger zz_frenar_masivo after delete on public.lab_charges
referencing old table as borradas
for each statement execute function public.frenar_borrado_masivo();

alter table public.lab_charges enable row level security;
create policy lab_charges_select_own on public.lab_charges
for select to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'
  )
);
revoke all on public.lab_charges from anon;
revoke insert, update, delete, truncate on public.lab_charges from authenticated;
grant select on public.lab_charges to authenticated;

-- Lab de un cargo según los labs del rollo. Las vistas repiten este case en
-- línea porque corren con los permisos de quien lee.
create function app_private.charge_lab(p_kind text, p_dev_lab bigint, p_scan_lab bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case p_kind
           when 'scan' then p_scan_lab
           when 'dev' then p_dev_lab
           else coalesce(p_dev_lab, p_scan_lab)
         end
$$;
revoke all on function app_private.charge_lab(text, bigint, bigint) from public, anon, authenticated;

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
     set film_stock_id = old.film_stock_id, format = old.format
   where roll_id = old.id and origin = 'roll' and owner_user_id = old.owner_user_id;
  update public.lab_charges
     set lab_id = app_private.charge_lab(kind, old.dev_lab_id, old.scan_lab_id), roll_code = old.code
   where roll_id = old.id and owner_user_id = old.owner_user_id;
  return old;
end;
$$;

-- Los costos de laboratorio de un rollo como estado deseado. La app manda los
-- cargos que tenía a la vista y los que quiere; todo cambia en una sola
-- transacción, o nada si alguien más lo cambió antes.
create function public.lab_costs_save(
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

  -- Lo que la app tenía a la vista debe ser exactamente lo activo ahora.
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
revoke all on function public.lab_costs_save(uuid, bigint, jsonb, jsonb) from public, anon;
grant execute on function public.lab_costs_save(uuid, bigint, jsonb, jsonb) to authenticated;

-- Costos de cada rollo para la Ficha: el film (del inventario o de la Ficha),
-- los cargos de lab activos con el lab vivo del rollo, y un total por moneda.
create view public.roll_costs with (security_invoker = true) as
with film as (
  select o.roll_id, o.owner_user_id, o.unit_price_minor, o.currency,
         jsonb_build_object('origin', o.origin, 'purchase_id', o.purchase_id,
                            'unit_price_minor', o.unit_price_minor, 'currency', o.currency,
                            'purchased_on', o.purchased_on, 'version', o.purchase_version) as film
  from public.roll_film_origin o
),
lab as (
  select c.roll_id, c.owner_user_id,
         jsonb_agg(jsonb_build_object(
           'id', c.id, 'kind', c.kind, 'amount_minor', c.amount_minor, 'currency', c.currency,
           'charged_on', c.charged_on, 'version', c.version,
           'lab_id', case c.kind
                       when 'scan' then r.scan_lab_id
                       when 'dev' then r.dev_lab_id
                       else coalesce(r.dev_lab_id, r.scan_lab_id)
                     end)
           order by array_position(array['dev_scan', 'dev', 'scan'], c.kind)) as lab
  from public.lab_charges c
  join public.rolls r on r.id = c.roll_id
  where c.voided_at is null
  group by c.roll_id, c.owner_user_id
),
amounts as (
  select roll_id, currency, unit_price_minor as amount_minor
  from film where unit_price_minor is not null
  union all
  select c.roll_id, c.currency, c.amount_minor
  from public.lab_charges c
  where c.voided_at is null and c.roll_id is not null
),
totals as (
  select roll_id, jsonb_agg(jsonb_build_object('currency', currency, 'amount_minor', amount_minor)
                            order by currency) as totals
  from (select roll_id, currency, sum(amount_minor)::bigint as amount_minor
        from amounts group by roll_id, currency) t
  group by roll_id
)
select coalesce(f.roll_id, l.roll_id) as roll_id,
       coalesce(f.owner_user_id, l.owner_user_id) as owner_user_id,
       f.film,
       coalesce(l.lab, '[]'::jsonb) as lab,
       coalesce(t.totals, '[]'::jsonb) as totals
from film f
full join lab l on l.roll_id = f.roll_id
left join totals t on t.roll_id = coalesce(f.roll_id, l.roll_id);

revoke all on public.roll_costs from public, anon, authenticated;
grant select on public.roll_costs to authenticated;
