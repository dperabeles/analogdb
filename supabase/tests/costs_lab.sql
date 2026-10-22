-- Lab charges per roll and the per-roll costs view (ANA-184).
-- Run inside BEGIN / ROLLBACK after film_inventory_helpers.sql, also
-- immediately after applying the migration. Synthetic accounts only.
do $$
declare
  a uuid; b uuid; nn uuid;
  portra bigint;
  l1 bigint; l2 bigint; l3 bigint;
  r bigint; rb bigint; rc bigint; r2 bigint;
  res jsonb; res2 jsonb; stale jsonb;
  cmd uuid := gen_random_uuid();
  sep jsonb := '[{"kind":"dev","amount_minor":18000,"currency":"MXN","charged_on":"2026-05-02"},
                 {"kind":"scan","amount_minor":12000,"currency":"MXN","charged_on":"2026-05-02"}]';
  dev_id uuid; scan_id uuid;
  rows_before bigint; archived bigint;
  bad text;
begin
  a := pg_temp.inv_user('cla');
  b := pg_temp.inv_user('clb');
  nn := pg_temp.inv_user('cln');
  perform pg_temp.inv_member(a, 'costs');
  perform pg_temp.inv_member(b, 'costs');
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog)
  values ('Prueba Cost', 'Portra Lab', 400, 'COLOR', false) returning id into portra;
  insert into public.labs (name, status) values ('Lab Costos Uno', 'approved') returning id into l1;
  insert into public.labs (name, status) values ('Lab Costos Dos', 'approved') returning id into l2;
  insert into public.labs (name, status) values ('Lab Costos Tres', 'approved') returning id into l3;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, dev_lab_id, scan_lab_id)
  values (a, 'R911', gen_random_uuid(), portra, 35, 'Developed', l1, l2) returning id into r;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (b, 'R912', gen_random_uuid(), portra, 35, 'Developed') returning id into rb;
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status)
  values (a, 'R913', gen_random_uuid(), portra, 35, 'In Camera') returning id into rc;

  -- Rev + Scan together, at the development lab.
  perform pg_temp.como(a);
  res := public.lab_costs_save(gen_random_uuid(), r, '[]',
    '[{"kind":"dev_scan","amount_minor":30000,"currency":"MXN","charged_on":"2026-05-02"}]');
  assert jsonb_array_length(res -> 'charges') = 1 and res -> 'charges' -> 0 ->> 'kind' = 'dev_scan', 'one combined charge';
  assert res -> 'voided' = '[]'::jsonb, 'nothing voided';
  assert (select (lab -> 0 ->> 'lab_id')::bigint from public.roll_costs where roll_id = r) = l1, 'combined at the dev lab';

  -- Split into Rev and Scan: the combined one is voided in the same call.
  res2 := public.lab_costs_save(cmd, r, res -> 'charges', sep);
  assert res2 -> 'voided' -> 0 ->> 'id' = res -> 'charges' -> 0 ->> 'id', 'combined voided';
  assert jsonb_array_length(res2 -> 'charges') = 2, 'two separate charges';
  assert public.lab_costs_save(cmd, r, res -> 'charges', sep) = res2, 'replay returns the same receipt';
  assert (select (e ->> 'lab_id')::bigint from public.roll_costs c, jsonb_array_elements(c.lab) e
          where c.roll_id = r and e ->> 'kind' = 'scan') = l2, 'scan at the scan lab';
  assert (select totals from public.roll_costs where roll_id = r)
       = '[{"currency":"MXN","amount_minor":30000}]'::jsonb, 'total of the lab, film unknown';
  assert (select film from public.roll_costs where roll_id = r) is null, 'no film price yet';
  perform pg_temp.espera_error(format('select public.lab_costs_save(%L, %s, %L, %L)',
    cmd, r, res2 -> 'charges', '[]'), 'P1106');

  -- Only Rev: Scan is voided, Rev keeps its version because it did not change.
  stale := res2 -> 'charges';
  res := public.lab_costs_save(gen_random_uuid(), r, stale,
    '[{"kind":"dev","amount_minor":18000,"currency":"MXN","charged_on":"2026-05-02"}]');
  assert res -> 'voided' -> 0 ->> 'kind' = 'scan', 'scan voided';
  assert (res -> 'charges' -> 0 ->> 'version')::int = 1, 'unchanged charge keeps its version';

  -- A stale view conflicts, also when the same command is sent again.
  perform pg_temp.yo();
  rows_before := (select count(*) from public.lab_charges where roll_id = r);
  perform pg_temp.como(a);
  cmd := gen_random_uuid();
  perform pg_temp.espera_error(format('select public.lab_costs_save(%L, %s, %L, %L)', cmd, r, stale, '[]'), 'P1105');
  perform pg_temp.espera_error(format('select public.lab_costs_save(%L, %s, %L, %L)', cmd, r, stale, '[]'), 'P1105');
  perform pg_temp.yo();
  assert (select count(*) from public.lab_charges where roll_id = r) = rows_before, 'conflicts write nothing';

  -- Void everything: the roll has no costs left.
  perform pg_temp.como(a);
  res := public.lab_costs_save(gen_random_uuid(), r, res -> 'charges', '[]');
  assert res -> 'charges' = '[]'::jsonb and jsonb_array_length(res -> 'voided') = 1, 'all voided';
  assert not exists (select 1 from public.roll_costs where roll_id = r), 'no costs left on the roll';

  -- Invalid requests change nothing.
  foreach bad in array array[
    '[{"kind":"dev_scan","amount_minor":1,"currency":"MXN"},{"kind":"dev","amount_minor":1,"currency":"MXN"}]',
    '[{"kind":"dev","amount_minor":1,"currency":"MXN"},{"kind":"dev","amount_minor":2,"currency":"MXN"}]',
    '[{"kind":"print","amount_minor":1,"currency":"MXN"}]',
    '[{"kind":"dev","amount_minor":-1,"currency":"MXN"}]',
    '[{"kind":"dev","amount_minor":1.5,"currency":"MXN"}]',
    '[{"kind":"dev","amount_minor":"100","currency":"MXN"}]',
    '[{"kind":"dev","currency":"MXN"}]',
    '[{"kind":"dev","amount_minor":1,"currency":"ZZZ"}]',
    '[{"kind":"dev","amount_minor":1,"currency":"MXN","charged_on":"2026-13-01"}]',
    '[{"kind":"dev","amount_minor":1,"currency":"MXN","charged_on":"mañana"}]',
    '[{"kind":"dev","amount_minor":1,"currency":"MXN","charged_on":"today"}]',
    '[{"kind":"dev","amount_minor":1,"currency":"MXN","charged_on":20260101}]',
    '[{"kind":"dev","amount_minor":1,"currency":"MXN","charged_on":"' || to_char(current_date + 2, 'YYYY-MM-DD') || '"}]',
    '{"kind":"dev"}',
    '["dev"]'
  ] loop
    perform pg_temp.espera_error(format('select public.lab_costs_save(gen_random_uuid(), %s, %L, %L)',
      r, '[]', bad), 'P1103');
  end loop;
  perform pg_temp.espera_error(format('select public.lab_costs_save(gen_random_uuid(), %s, %L, %L)',
    r, '[{"id":"x","version":1}]', '[]'), 'P1103');

  -- Each service keeps its own currency; totals never mix them.
  res := public.lab_costs_save(gen_random_uuid(), r, '[]',
    '[{"kind":"dev","amount_minor":18000,"currency":"MXN","charged_on":"2026-06-01"},
      {"kind":"scan","amount_minor":1000,"currency":"USD","charged_on":null}]');
  assert (select totals from public.roll_costs where roll_id = r)
       = '[{"currency":"MXN","amount_minor":18000},{"currency":"USD","amount_minor":1000}]'::jsonb, 'one total per currency';
  select (e ->> 'id')::uuid into dev_id from jsonb_array_elements(res -> 'charges') e where e ->> 'kind' = 'dev';
  select (e ->> 'id')::uuid into scan_id from jsonb_array_elements(res -> 'charges') e where e ->> 'kind' = 'scan';
  perform pg_temp.yo();

  -- The lab follows the roll: an edit, then a lab merge (what admin_merge_labs does).
  update public.rolls set dev_lab_id = l2 where id = r;
  assert (select (e ->> 'lab_id')::bigint from public.roll_costs c, jsonb_array_elements(c.lab) e
          where c.roll_id = r and e ->> 'kind' = 'dev') = l2, 'follows the roll lab';
  update public.rolls set dev_lab_id = l3 where dev_lab_id = l2;
  update public.rolls set scan_lab_id = l3 where scan_lab_id = l2;
  update public.labs set active = false, merged_into_id = l3 where id = l2;
  assert (select string_agg(e ->> 'lab_id', ',' order by e ->> 'kind') from public.roll_costs c, jsonb_array_elements(c.lab) e
          where c.roll_id = r) = l3 || ',' || l3, 'follows a lab merge';

  -- Changed again, then deleted the usual way with more than 5 frames: the
  -- charges keep the last lab and the code, and stay active.
  update public.rolls set dev_lab_id = l1 where id = r;
  insert into public.roll_exposures (roll_id, frame_number) select r, n from generate_series(1, 8) n;
  perform pg_temp.como(a);
  delete from public.rolls where id = r;
  perform pg_temp.yo();
  assert (select roll_id is null and lab_id = l1 and roll_code = 'R911' and voided_at is null
          from public.lab_charges where id = dev_id), 'dev frozen with its last lab';
  assert (select lab_id = l3 and roll_code = 'R911' from public.lab_charges where id = scan_id), 'scan frozen too';
  assert (select count(*) from public.lab_charges where roll_code = 'R911' and voided_at is not null) = 3,
         'voided charges are frozen as well';

  -- A new roll gets its own Rev; a roll still in the camera accepts charges.
  insert into public.rolls (owner_user_id, code, client_uuid, film_stock_id, format, status, dev_lab_id)
  values (a, 'R914', gen_random_uuid(), portra, 35, 'Developed', l1) returning id into r2;
  perform pg_temp.como(a);
  perform public.lab_costs_save(gen_random_uuid(), r2, '[]', '[{"kind":"dev","amount_minor":9000,"currency":"MXN"}]');
  perform public.lab_costs_save(gen_random_uuid(), rc, '[]', '[{"kind":"dev_scan","amount_minor":1,"currency":"MXN"}]');

  -- Another account's roll; an account without the costs feature.
  perform pg_temp.espera_error(format('select public.lab_costs_save(gen_random_uuid(), %s, %L, %L)',
    rb, '[]', '[{"kind":"dev","amount_minor":1,"currency":"MXN"}]'), 'P1109');
  perform pg_temp.yo();
  assert not exists (select 1 from public.lab_charges where roll_id = rb), 'B roll untouched';
  perform pg_temp.como(nn);
  perform pg_temp.espera_error(format('select public.lab_costs_save(gen_random_uuid(), %s, %L, %L)',
    rc, '[]', '[]'), 'P1102');
  perform pg_temp.yo();

  -- Last: deleting the account leaves no charges and archives nothing new.
  select count(*) into archived from public.deleted_rows where dueno = a;
  perform pg_temp.como(a);
  perform public.delete_my_account();
  perform pg_temp.yo();
  assert not exists (select 1 from public.lab_charges where owner_user_id = a), 'charges gone';
  assert (select count(*) from public.deleted_rows where dueno = a) = archived, 'no new archived copies';
  assert not exists (select 1 from public.deleted_rows where dueno = a and tabla = 'lab_charges'), 'no archived charges';
end $$;
