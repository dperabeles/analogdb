-- ANA-173: base del inventario de film con precio.
--
-- Catálogo de monedas, moneda predeterminada de cada cuenta, acceso por cuenta
-- a funciones nuevas y recibos de comandos para que un reintento nunca
-- duplique nada. Las tablas se leen por RLS; solo las funciones escriben.

-- Monedas vigentes de ISO 4217 con sus decimales oficiales. Sin metales,
-- unidades de cuenta, códigos de prueba ni códigos de fondos. Los nombres los
-- traduce la app.
create table public.currencies (
  code char(3) primary key check (code ~ '^[A-Z]{3}$'),
  minor_unit smallint not null check (minor_unit between 0 and 4),
  active boolean not null default true
);

insert into public.currencies (code, minor_unit)
select code, 2 from unnest(array[
  'AED','AFN','ALL','AMD','ANG','AOA','ARS','AUD','AWG','AZN','BAM','BBD','BDT',
  'BGN','BHD','BIF','BMD','BND','BOB','BRL','BSD','BTN','BWP','BYN','BZD','CAD',
  'CDF','CHF','CLP','CNY','COP','CRC','CUP','CVE','CZK','DJF','DKK','DOP','DZD',
  'EGP','ERN','ETB','EUR','FJD','FKP','GBP','GEL','GHS','GIP','GMD','GNF','GTQ',
  'GYD','HKD','HNL','HTG','HUF','IDR','ILS','INR','IQD','IRR','ISK','JMD','JOD',
  'JPY','KES','KGS','KHR','KMF','KPW','KRW','KWD','KYD','KZT','LAK','LBP','LKR',
  'LRD','LSL','LYD','MAD','MDL','MGA','MKD','MMK','MNT','MOP','MRU','MUR','MVR',
  'MWK','MXN','MYR','MZN','NAD','NGN','NIO','NOK','NPR','NZD','OMR','PAB','PEN',
  'PGK','PHP','PKR','PLN','PYG','QAR','RON','RSD','RUB','RWF','SAR','SBD','SCR',
  'SDG','SEK','SGD','SHP','SLE','SOS','SRD','SSP','STN','SVC','SYP','SZL','THB',
  'TJS','TMT','TND','TOP','TRY','TTD','TWD','TZS','UAH','UGX','USD','UYU','UZS',
  'VED','VES','VND','VUV','WST','XAF','XCD','XCG','XOF','XPF','YER','ZAR','ZMW',
  'ZWG'
]) as code;

update public.currencies set minor_unit = 0 where code in (
  'BIF','CLP','DJF','GNF','ISK','JPY','KMF','KRW','PYG','RWF','UGX','VND','VUV',
  'XAF','XOF','XPF'
);
update public.currencies set minor_unit = 3 where code in (
  'BHD','IQD','JOD','KWD','LYD','OMR','TND'
);

alter table public.currencies enable row level security;
create policy currencies_read on public.currencies
for select to authenticated using (true);
revoke all on public.currencies from anon;
revoke insert, update, delete, truncate on public.currencies from authenticated;
grant select on public.currencies to authenticated;

-- Solo preselecciona la moneda de capturas nuevas; nunca convierte nada guardado.
create table public.finance_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  default_currency char(3) not null references public.currencies(code),
  updated_at timestamptz not null default now()
);

alter table public.finance_preferences enable row level security;
create policy finance_preferences_select_own on public.finance_preferences
for select to authenticated
using (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'
  )
);
revoke all on public.finance_preferences from anon;
revoke insert, update, delete, truncate on public.finance_preferences from authenticated;
grant select on public.finance_preferences to authenticated;

-- Acceso por cuenta. `film_inventory` empieza cerrado: se abre por miembro
-- (la cuenta de Diego mientras corre el aviso de 30 días) o para todos.
create table app_private.feature_flags (
  feature text primary key,
  enabled_for_everyone boolean not null default false
);
insert into app_private.feature_flags (feature) values ('film_inventory');

create table app_private.feature_members (
  feature text not null references app_private.feature_flags(feature),
  user_id uuid not null references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  primary key (feature, user_id)
);
create index feature_members_user_id_idx on app_private.feature_members(user_id);

revoke all on app_private.feature_flags, app_private.feature_members from public, anon, authenticated;

-- Un recibo por comando: mismo id y misma petición devuelven el mismo
-- resultado; cualquier diferencia es un conflicto.
create table public.inventory_commands (
  command_id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  request_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
create index inventory_commands_owner_user_id_idx on public.inventory_commands(owner_user_id);

alter table public.inventory_commands enable row level security;
create policy inventory_commands_select_own on public.inventory_commands
for select to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'
  )
);
revoke all on public.inventory_commands from anon;
revoke insert, update, delete, truncate on public.inventory_commands from authenticated;
grant select on public.inventory_commands to authenticated;

create function app_private.feature_enabled(p_user uuid, p_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select exists (
             select 1 from public.profiles p
             where p.user_id = p_user and p.status = 'approved'
           )
       and (f.enabled_for_everyone or exists (
             select 1 from app_private.feature_members m
             where m.feature = f.feature and m.user_id = p_user
           ))
    from app_private.feature_flags f
    where f.feature = p_feature
  ), false)
$$;

create function app_private.inventory_writer()
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
  if not app_private.feature_enabled(v_user, 'film_inventory') then
    raise exception 'not_enabled' using errcode = 'P1102';
  end if;
  return v_user;
end;
$$;

create function app_private.command_replay(
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

create function app_private.command_record(
  p_owner uuid, p_command_id uuid, p_kind text, p_request jsonb, p_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.inventory_commands (command_id, owner_user_id, kind, request_hash, result)
  values (p_command_id, p_owner, p_kind, md5(p_request::text), p_result);
  return p_result;
end;
$$;

revoke all on function app_private.feature_enabled(uuid, text) from public, anon, authenticated;
revoke all on function app_private.inventory_writer() from public, anon, authenticated;
revoke all on function app_private.command_replay(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function app_private.command_record(uuid, uuid, text, jsonb, jsonb) from public, anon, authenticated;

create function public.my_features()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(f.feature order by f.feature), '{}'::text[])
  from app_private.feature_flags f
  where auth.uid() is not null
    and app_private.feature_enabled(auth.uid(), f.feature)
$$;

create function public.set_default_currency(p_currency text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.inventory_writer();
begin
  if not exists (
    select 1 from public.currencies c where c.code = p_currency and c.active
  ) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  insert into public.finance_preferences (user_id, default_currency)
  values (v_user, p_currency)
  on conflict (user_id) do update
    set default_currency = excluded.default_currency, updated_at = now();
end;
$$;

revoke all on function public.my_features() from public, anon;
revoke all on function public.set_default_currency(text) from public, anon;
grant execute on function public.my_features() to authenticated;
grant execute on function public.set_default_currency(text) to authenticated;
