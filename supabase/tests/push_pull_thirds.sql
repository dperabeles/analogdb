-- Push/pull in thirds decides the ISO @ (20261122150000). Run inside
-- BEGIN / ROLLBACK after film_inventory_helpers.sql. Synthetic accounts only.
do $$
declare
  a uuid; portra bigint; dx bigint; r1 bigint; r2 bigint; r3 bigint;
begin
  -- How the text reads: whole stops as every build wrote them, and thirds.
  assert app_private.push_pull_thirds('0') = 0, '0';
  assert app_private.push_pull_thirds('+1') = 3, '+1';
  assert app_private.push_pull_thirds('-2') = -6, '-2';
  assert app_private.push_pull_thirds('−1') = -3, 'typographic minus';
  assert app_private.push_pull_thirds('+1⅓') = 4, '+1⅓';
  assert app_private.push_pull_thirds('-⅔') = -2, '-⅔';
  assert app_private.push_pull_thirds(' +⅓ ') = 1, '+⅓ with spaces';
  assert app_private.push_pull_thirds(null) is null, 'null';
  assert app_private.push_pull_thirds('mucho') is null, 'unreadable';
  assert app_private.push_pull_thirds('+') is null, 'a sign alone';

  -- The scale: the same table and the same answers as the app.
  assert app_private.iso_at_thirds(400, 4) = 1000, '400 +1⅓';
  assert app_private.iso_at_thirds(250, -1) = 200, '250 -⅓';
  assert app_private.iso_at_thirds(250, -4) = 100, '250 -1⅓';
  assert app_private.iso_at_thirds(800, -18) = 12, 'R073: 800 six stops down';
  assert app_private.iso_at_thirds(64, 3) = 125, '64 +1';
  assert app_private.iso_at_thirds(150, 0) = 150, 'zero leaves it';
  assert app_private.iso_at_thirds(150, 3) = 320, 'off the scale starts from the nearest';

  a := pg_temp.inv_user('ppthirds');
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Prueba PP', 'Portra PP', 400, 'COLOR', false, 'approved') returning id into portra;
  insert into public.film_stocks (manufacturer, name, iso, type, in_catalog, status)
  values ('Prueba PP', 'Double-X PP', 250, 'COLOR', false, 'approved') returning id into dx;

  perform pg_temp.como(a);
  -- A new roll with a push: the base fills the ISO @ (quick add, offline
  -- replay and the inventory load all send only the push/pull).
  insert into public.rolls (owner_user_id, code, client_uuid, status, film_stock_id, push_pull)
  values (a, 'PP-1', gen_random_uuid(), 'In Camera', portra, '+1⅓') returning id into r1;
  assert (select iso_pushed from public.rolls where id = r1) = 1000, 'a push fills the ISO @';

  insert into public.rolls (owner_user_id, code, client_uuid, status, film_stock_id, push_pull)
  values (a, 'PP-2', gen_random_uuid(), 'In Camera', portra, '0') returning id into r2;
  assert (select iso_pushed is null from public.rolls where id = r2), 'normal adds nothing';

  -- An ISO @ that comes with the roll stays.
  insert into public.rolls (owner_user_id, code, client_uuid, status, film_stock_id, push_pull, iso_pushed)
  values (a, 'PP-3', gen_random_uuid(), 'In Camera', portra, '+1', 640) returning id into r3;
  assert (select iso_pushed from public.rolls where id = r3) = 640, 'a written ISO @ on insert stays';

  -- Moving the push/pull works it out again; back to normal clears it.
  update public.rolls set push_pull = '-⅓' where id = r1;
  assert (select iso_pushed from public.rolls where id = r1) = 320, 'moved to -⅓';
  update public.rolls set push_pull = '0' where id = r1;
  assert (select iso_pushed is null from public.rolls where id = r1), 'back to normal';

  -- A save that sends the same push/pull keeps what was there.
  update public.rolls set notes = 'otra cosa', push_pull = '+1', iso_pushed = 640 where id = r3;
  assert (select iso_pushed from public.rolls where id = r3) = 640, 'an unrelated save keeps it';

  -- Another film works it out from the new box ISO.
  update public.rolls set film_stock_id = dx where id = r3;
  assert (select iso_pushed from public.rolls where id = r3) = 500, 'Double-X 250 +1';

  -- Text it cannot read leaves the ISO @ as written.
  update public.rolls set push_pull = 'mucho', iso_pushed = 200 where id = r2;
  assert (select iso_pushed from public.rolls where id = r2) = 200, 'unreadable leaves it';
  perform pg_temp.yo();

  assert (select "ISO @" from public.rolls_flat where id = r3) = 500, 'rolls_flat shows it';
  raise notice 'push_pull_thirds: all checks passed';
end $$;
