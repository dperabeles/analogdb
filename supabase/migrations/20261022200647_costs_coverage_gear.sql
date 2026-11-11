-- Costos (ANA-184): en la cobertura de Cifras, el equipo sin ninguna compra
-- capturada también cuenta como sin precio (decisión de Diego, 22-oct). Solo
-- en Todo, porque no tiene fecha.

-- Todos los números de Gastos en una moneda. p_year null es «Todo»: entra lo
-- que no tiene fecha. Un año solo cuenta lo pagado ese año. Ver la sección 8
-- de BACKEND-COSTOS.md.
create or replace function public.costs_summary(p_currency text, p_year integer)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if p_currency is null
     or not exists (select 1 from public.currencies c where c.code = p_currency)
     or (p_year is not null and (p_year < 1900 or p_year > 9999)) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;

  with o as (
    select e.* from public.expense_origins e
    where e.owner_user_id = v_uid
      and e.currency = p_currency
      and (p_year is null or extract(year from e.paid_on)::integer = p_year)
  ),
  evolution as (
    select coalesce(jsonb_agg(jsonb_build_object('period', g.period, 'amount_minor', coalesce(s.amount, 0))
                              order by g.period), '[]'::jsonb) as j
    from (
      select generate_series(1, 12) as period where p_year is not null
      union
      select extract(year from paid_on)::integer from o where p_year is null and paid_on is not null
    ) g
    left join (
      select case when p_year is null then extract(year from paid_on)::integer
                  else extract(month from paid_on)::integer end as period,
             sum(amount_minor)::bigint as amount
      from o where paid_on is not null
      group by 1
    ) s on s.period = g.period
  ),
  breakdown as (
    select jsonb_agg(jsonb_build_object('category', k.category, 'amount_minor', coalesce(s.amount, 0))
                     order by k.ord) as j
    from unnest(array['film', 'dev_scan', 'dev', 'scan', 'camera', 'lens']) with ordinality as k(category, ord)
    left join (select category, sum(amount_minor)::bigint as amount from o group by category) s
      on s.category = k.category
  ),
  -- Las compras en 0 (regalos) no entran al precio medio.
  film_avg as (
    select jsonb_build_object(
             'avg_minor', case when sum(quantity) > 0
                               then round(sum(amount_minor)::numeric / sum(quantity))::bigint end,
             'units', coalesce(sum(quantity), 0)::bigint) as j
    from o where category = 'film' and unit_price_minor > 0
  ),
  -- Rollos terminados del periodo según su fecha de término; cuentan los que
  -- tienen film y lab conocidos, todo en esta moneda.
  finished as (
    select r.id from public.rolls r
    where r.owner_user_id = v_uid
      and r.status in ('Developed', 'Archived')
      and (p_year is null or extract(year from r.finished)::integer = p_year)
  ),
  roll_cost as (
    select f.id,
           fo.unit_price_minor as film_minor,
           lab.amount as lab_minor,
           fo.unit_price_minor is not null and fo.currency = p_currency
             and lab.other_currency = 0
             and (lab.dev_scan > 0 or (lab.dev > 0 and lab.scan > 0)) as complete
    from finished f
    left join public.roll_film_origin fo on fo.roll_id = f.id
    cross join lateral (
      select coalesce(sum(c.amount_minor), 0)::bigint as amount,
             count(*) filter (where c.currency <> p_currency) as other_currency,
             count(*) filter (where c.kind = 'dev_scan') as dev_scan,
             count(*) filter (where c.kind = 'dev') as dev,
             count(*) filter (where c.kind = 'scan') as scan
      from public.lab_charges c
      where c.roll_id = f.id and c.voided_at is null
    ) lab
  ),
  roll_avg as (
    select jsonb_build_object(
             'avg_minor', case when count(*) filter (where complete) > 0
                               then round(sum(film_minor + lab_minor) filter (where complete)::numeric
                                          / count(*) filter (where complete))::bigint end,
             'rolls_counted', count(*) filter (where complete),
             'rolls_finished', count(*),
             'rolls_without_finish', (select count(*) from public.rolls r
                                      where r.owner_user_id = v_uid
                                        and r.status in ('Developed', 'Archived')
                                        and r.finished is null)) as j
    from roll_cost
  ),
  -- Foto de hoy, sin periodo.
  inventory as (
    select jsonb_build_object(
             'value_minor', coalesce(sum(p.unit_price_minor) filter (where p.currency = p_currency), 0)::bigint,
             'units_priced', count(*) filter (where p.currency = p_currency),
             'units_unpriced', count(*) filter (where p.unit_price_minor is null)) as j
    from public.film_units u
    left join public.film_purchases p on p.id = u.purchase_id
    where u.owner_user_id = v_uid and u.status = 'available'
  ),
  film_details as (
    select coalesce(jsonb_agg(jsonb_build_object('film_stock_id', film_stock_id, 'format', format,
                                                 'amount_minor', amount, 'units', units)
                              order by amount desc, film_stock_id, format), '[]'::jsonb) as j
    from (select film_stock_id, format, sum(amount_minor)::bigint as amount, sum(quantity)::bigint as units
          from o where category = 'film'
          group by film_stock_id, format) t
  ),
  lab_details as (
    select coalesce(jsonb_agg(jsonb_build_object('lab_id', lab_id, 'dev_scan_minor', ds, 'dev_minor', d,
                                                 'scan_minor', s, 'amount_minor', ds + d + s)
                              order by ds + d + s desc, lab_id nulls last), '[]'::jsonb) as j
    from (select lab_id,
                 coalesce(sum(amount_minor) filter (where category = 'dev_scan'), 0)::bigint as ds,
                 coalesce(sum(amount_minor) filter (where category = 'dev'), 0)::bigint as d,
                 coalesce(sum(amount_minor) filter (where category = 'scan'), 0)::bigint as s
          from o where category in ('dev_scan', 'dev', 'scan')
          group by lab_id) t
  ),
  -- Lo que no tiene precio no tiene moneda: se cuenta sin filtrarla.
  coverage as (
    select jsonb_build_object(
             'film_units_unpriced', (select coalesce(sum(p.quantity), 0)::bigint from public.film_purchases p
                                     where p.owner_user_id = v_uid and p.voided_at is null
                                       and p.unit_price_minor is null
                                       and (p_year is null or extract(year from p.purchased_on)::integer = p_year)),
             'equipment_unpriced',
               (select count(*) from public.equipment_purchases e
                where e.owner_user_id = v_uid and e.voided_at is null
                  and e.amount_minor is null
                  and (p_year is null or extract(year from e.purchased_on)::integer = p_year))
               -- En Todo cuentan también las cámaras y lentes sin ninguna
               -- compra activa: no tienen fecha, así que un año no las ve.
               + case when p_year is null then
                   (select count(*) from public.cameras c
                    where c.owner_user_id = v_uid
                      and not exists (select 1 from public.equipment_purchases e
                                      where e.kind = 'camera' and e.source_item_id = c.id
                                        and e.voided_at is null))
                   + (select count(*) from public.lenses l
                      where l.owner_user_id = v_uid
                        and not exists (select 1 from public.equipment_purchases e
                                        where e.kind = 'lens' and e.source_item_id = l.id
                                          and e.voided_at is null))
                 else 0 end) as j
  )
  select jsonb_build_object(
           'currency', p_currency,
           'year', p_year,
           'total_minor', (select coalesce(sum(amount_minor), 0)::bigint from o),
           'undated_minor', (select coalesce(sum(amount_minor), 0)::bigint from o where paid_on is null),
           'evolution', (select j from evolution),
           'breakdown', (select j from breakdown),
           'film_avg', (select j from film_avg),
           'roll_avg', (select j from roll_avg),
           'inventory', (select j from inventory),
           'film_details', (select j from film_details),
           'lab_details', (select j from lab_details),
           'coverage', (select j from coverage))
    into v_result;
  return v_result;
end;
$$;
revoke all on function public.costs_summary(text, integer) from public, anon;
grant execute on function public.costs_summary(text, integer) to authenticated;
