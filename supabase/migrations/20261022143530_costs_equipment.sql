-- Costos (ANA-184), parte 3: compra de cámaras y lentes. Una compra activa
-- por pieza; importe, fecha o ambos. Borrar el equipo no borra la compra.

create table public.equipment_purchases (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('camera', 'lens')),
  camera_id bigint references public.cameras(id) on delete set null,
  lens_id bigint references public.lenses(id) on delete set null,
  -- Marca y modelo; solo se llena al borrar el equipo.
  label text,
  amount_minor bigint check (amount_minor between 0 and 1000000000000),
  currency char(3) references public.currencies(code),
  purchased_on date,
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  constraint equipment_purchases_camera_ref check (kind = 'camera' or camera_id is null),
  constraint equipment_purchases_lens_ref check (kind = 'lens' or lens_id is null),
  constraint equipment_purchases_amount_has_currency check ((amount_minor is null) = (currency is null)),
  constraint equipment_purchases_something_known check (amount_minor is not null or purchased_on is not null)
);
create index equipment_purchases_owner_user_id_idx on public.equipment_purchases(owner_user_id);
create index equipment_purchases_camera_id_idx on public.equipment_purchases(camera_id);
create index equipment_purchases_lens_id_idx on public.equipment_purchases(lens_id);
create index equipment_purchases_currency_idx on public.equipment_purchases(currency);
create unique index equipment_purchases_active_camera_uidx on public.equipment_purchases(camera_id)
  where camera_id is not null and voided_at is null;
create unique index equipment_purchases_active_lens_uidx on public.equipment_purchases(lens_id)
  where lens_id is not null and voided_at is null;

create trigger equipment_purchases_touch before update on public.equipment_purchases
for each row execute function public.touch_updated_at();
create trigger zz_archivar_borrado before delete on public.equipment_purchases
for each row execute function public.archivar_fila_borrada();
create trigger zz_frenar_masivo after delete on public.equipment_purchases
referencing old table as borradas
for each statement execute function public.frenar_borrado_masivo();

alter table public.equipment_purchases enable row level security;
create policy equipment_purchases_select_own on public.equipment_purchases
for select to authenticated
using (
  owner_user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.user_id = (select auth.uid()) and p.status = 'approved'
  )
);
revoke all on public.equipment_purchases from anon;
revoke insert, update, delete, truncate on public.equipment_purchases from authenticated;
grant select on public.equipment_purchases to authenticated;

-- Al borrar una cámara o una lente, su compra guarda marca y modelo.
create function app_private.costs_freeze_equipment()
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
       set label = btrim(coalesce(old.maker, '') || ' ' || coalesce(old.model, ''))
     where camera_id = old.id and owner_user_id = old.owner_user_id;
  else
    update public.equipment_purchases
       set label = btrim(coalesce(old.maker, '') || ' ' || coalesce(old.model, ''))
     where lens_id = old.id and owner_user_id = old.owner_user_id;
  end if;
  return old;
end;
$$;
revoke all on function app_private.costs_freeze_equipment() from public, anon, authenticated;

create trigger costs_freeze_equipment before delete on public.cameras
for each row execute function app_private.costs_freeze_equipment();
create trigger costs_freeze_equipment before delete on public.lenses
for each row execute function app_private.costs_freeze_equipment();

-- Compra de una cámara o lente: crea, corrige con versión, o anula si
-- importe, moneda y fecha llegan vacíos.
create function public.equipment_cost_set(
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
  where voided_at is null
    and ((p_kind = 'camera' and camera_id = p_item_id) or (p_kind = 'lens' and lens_id = p_item_id))
  for update;
  if (v_purchase.id is null) <> (p_expected_version is null)
     or v_purchase.version is distinct from p_expected_version then
    raise exception 'version_conflict' using errcode = 'P1105';
  end if;

  if v_clear and v_purchase.id is null then
    v_result := jsonb_build_object('id', null, 'version', null, 'active', false);
  elsif v_clear then
    update public.equipment_purchases set voided_at = now(), version = version + 1
    where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', false);
  elsif v_purchase.id is null then
    insert into public.equipment_purchases (owner_user_id, kind, camera_id, lens_id,
                                            amount_minor, currency, purchased_on)
    values (v_user, p_kind,
            case when p_kind = 'camera' then p_item_id end,
            case when p_kind = 'lens' then p_item_id end,
            p_amount_minor, p_currency, p_purchased_on)
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  else
    update public.equipment_purchases
       set amount_minor = p_amount_minor, currency = p_currency,
           purchased_on = p_purchased_on, version = version + 1
     where id = v_purchase.id
    returning * into v_purchase;
    v_result := jsonb_build_object('id', v_purchase.id, 'version', v_purchase.version, 'active', true);
  end if;

  return app_private.command_record(v_user, p_command_id, 'equipment_cost_set', v_request, v_result);
end;
$$;
revoke all on function public.equipment_cost_set(uuid, text, bigint, integer, bigint, text, date) from public, anon;
grant execute on function public.equipment_cost_set(uuid, text, bigint, integer, bigint, text, date) to authenticated;
