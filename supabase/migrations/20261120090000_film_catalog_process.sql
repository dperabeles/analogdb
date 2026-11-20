-- Catálogo de films, Fase 2d (Diego, 19-nov): el proceso de cada film,
-- las versiones de cine sin remjet, la línea nueva de Kodak y la de Reflx Lab,
-- y la limpieza de duplicados.
--
-- · Un proceso más, «ECN-2/C-41»: film de cine sin remjet (AHU, CineStill,
--   Gallostill, MARIX), que se revela de las dos formas.
-- · Los films se buscan por su clave (fabricante y nombre), no por número:
--   la misma migración sirve en staging y en producción. Solo se llena un
--   proceso vacío; lo que alguien ya corrigió no se pisa.
-- · Las fusiones y ediciones quedan en catalog_changes, como si se hubieran
--   hecho desde el panel, y se pueden deshacer desde ahí.

alter table public.film_stocks drop constraint if exists film_stocks_process_check;
alter table public.film_stocks add constraint film_stocks_process_check
  check (process is null or process in ('C-41', 'E-6', 'ECN-2', 'ECN-2/C-41', 'BW', 'OTHER'));

create function app_private.film_process_ok(p_process text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_process is null
      or p_process in ('C-41', 'E-6', 'ECN-2', 'ECN-2/C-41', 'BW', 'OTHER')
$$;
revoke all on function app_private.film_process_ok(text) from public, anon, authenticated;

create or replace function public.propose_film_stock(
  p_manufacturer_id bigint,
  p_name text,
  p_iso integer default null,
  p_type text default null,
  p_process text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := app_private.require_approved();
  v_maker public.manufacturers;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_key text;
  v_id bigint;
begin
  select * into v_maker from public.manufacturers m
   where m.id = p_manufacturer_id
     and (m.status = 'approved'
          or (m.created_by = v_user and m.status in ('pending', 'rejected')));
  if not found
     or v_name = '' or length(v_name) > 80
     or (p_iso is not null and p_iso not between 1 and 25600)
     or (p_type is not null and p_type not in ('COLOR', 'B/W', 'SLIDE'))
     or not app_private.film_process_ok(p_process) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  v_key := app_private.film_stock_key(v_maker.name, v_name);
  perform pg_advisory_xact_lock(hashtextextended('film_stock:' || v_key, 0));
  select s.id into v_id from public.film_stocks s
   where s.status = 'approved' and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
  if found then return v_id; end if;
  select s.id into v_id from public.film_stocks s
   where s.created_by = v_user and s.status in ('pending', 'rejected')
     and app_private.film_stock_key(s.manufacturer, s.name) = v_key;
  if found then return v_id; end if;
  insert into public.film_stocks
    (manufacturer, manufacturer_id, name, iso, type, process, in_catalog, status, created_by)
  values (v_maker.name, v_maker.id, v_name, p_iso, p_type, p_process, false, 'pending', v_user)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.admin_film_stock_update(
  p_id bigint,
  p_manufacturer_id bigint,
  p_name text,
  p_iso integer,
  p_type text,
  p_process text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := app_private.require_admin();
  v_film public.film_stocks;
  v_maker public.manufacturers;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_before jsonb;
  v_change bigint;
begin
  select * into v_film from public.film_stocks where id = p_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P1109';
  end if;
  v_before := app_private.film_stock_snapshot(v_film);
  if v_film.status not in ('pending', 'approved', 'rejected') then
    raise exception 'merge_chain' using errcode = 'P1114';
  end if;
  select * into v_maker from public.manufacturers m
   where m.id = p_manufacturer_id
     and (m.status = 'approved'
          or (m.status in ('pending', 'rejected') and m.created_by = v_film.created_by));
  if not found
     or v_name = '' or length(v_name) > 80
     or (p_iso is not null and p_iso not between 1 and 25600)
     or (p_type is not null and p_type not in ('COLOR', 'B/W', 'SLIDE'))
     or not app_private.film_process_ok(p_process) then
    raise exception 'invalid_input' using errcode = 'P1103';
  end if;
  begin
    update public.film_stocks
       set manufacturer_id = v_maker.id, name = v_name, iso = p_iso, type = p_type,
           process = p_process
     where id = p_id
    returning * into v_film;
  exception when unique_violation then
    raise exception 'name_taken' using errcode = 'P1113';
  end;
  insert into public.catalog_changes (entity, entity_id, action, before, after, changed_by)
  values ('film_stock', p_id, 'edit', v_before, app_private.film_stock_snapshot(v_film), v_admin)
  returning id into v_change;
  return v_change;
end;
$$;

-- ── Limpieza: duplicados y Gallostill bajo Kodak ──────────────────────────

create function pg_temp.catalog_merge(p_from_maker text, p_from_name text,
                                      p_into_maker text, p_into_name text)
returns void
language plpgsql
as $$
declare
  v_from public.film_stocks;
  v_into public.film_stocks;
  v_moved jsonb;
begin
  select * into v_from from public.film_stocks
   where status = 'approved'
     and app_private.film_stock_key(manufacturer, name) = app_private.film_stock_key(p_from_maker, p_from_name);
  select * into v_into from public.film_stocks
   where status = 'approved'
     and app_private.film_stock_key(manufacturer, name) = app_private.film_stock_key(p_into_maker, p_into_name);
  if v_from.id is null or v_into.id is null then
    return;  -- not in this database
  end if;
  v_moved := jsonb_build_object(
    'rolls', coalesce((select jsonb_agg(id) from public.rolls where film_stock_id = v_from.id), '[]'),
    'units', coalesce((select jsonb_agg(id) from public.film_units where film_stock_id = v_from.id), '[]'),
    'purchases', coalesce((select jsonb_agg(id) from public.film_purchases where film_stock_id = v_from.id), '[]'),
    'favorites', coalesce((select jsonb_agg(user_id) from public.profile_preferences
                           where favorite_film_stock_id = v_from.id), '[]'));
  perform app_private.merge_film_stock(v_from.id, v_into.id);
  insert into public.catalog_changes (entity, entity_id, action, target_id, before, after, moved)
  values ('film_stock', v_from.id, 'merge', v_into.id, app_private.film_stock_snapshot(v_from),
          app_private.film_stock_snapshot((select f from public.film_stocks f where f.id = v_from.id)),
          v_moved);
end;
$$;

select pg_temp.catalog_merge('Kodak', 'Double X', 'Kodak', 'Double-X');
select pg_temp.catalog_merge('Kodak', 'Gallostill 800T', 'Gallostill', '800T');

-- «Kodak Gallostill 400D» es de la marca Gallostill.
do $$
declare
  v public.film_stocks;
  v_maker bigint;
begin
  select * into v from public.film_stocks
   where status = 'approved'
     and app_private.film_stock_key(manufacturer, name) = app_private.film_stock_key('Kodak', 'Gallostill 400D');
  if v.id is null then return; end if;
  v_maker := app_private.manufacturer_for('Gallostill', null, true);
  update public.film_stocks set manufacturer_id = v_maker, name = '400D' where id = v.id;
  insert into public.catalog_changes (entity, entity_id, action, before, after)
  values ('film_stock', v.id, 'edit', app_private.film_stock_snapshot(v),
          app_private.film_stock_snapshot((select f from public.film_stocks f where f.id = v.id)));
end $$;

-- T-MAX P3200 se usa a 3200 (Diego).
do $$
declare
  v public.film_stocks;
begin
  select * into v from public.film_stocks
   where status = 'approved'
     and app_private.film_stock_key(manufacturer, name) = app_private.film_stock_key('Kodak', 'T-MAX P3200');
  if v.id is null or v.iso = 3200 then return; end if;
  update public.film_stocks set iso = 3200 where id = v.id;
  insert into public.catalog_changes (entity, entity_id, action, before, after)
  values ('film_stock', v.id, 'edit', app_private.film_stock_snapshot(v),
          app_private.film_stock_snapshot((select f from public.film_stocks f where f.id = v.id)));
end $$;

-- ── Films nuevos: Kodak (24-mar-2026), Vision3 AHU y Reflx Lab ────────────

insert into public.film_stocks (manufacturer, name, iso, type, process, in_catalog, status)
select m, n, i, t, p, true, 'approved'
from (values
  ('Kodak', 'Ektacolor Pro 160', 160, 'COLOR', 'C-41'),
  ('Kodak', 'Ektacolor Pro 400', 400, 'COLOR', 'C-41'),
  ('Kodak', 'Ektacolor Pro 800', 800, 'COLOR', 'C-41'),
  ('Kodak', 'Ektapan 100', 100, 'B/W', 'BW'),
  ('Kodak', 'Ektapan 400', 400, 'B/W', 'BW'),
  ('Kodak', 'Ektapan P3200', 3200, 'B/W', 'BW'),
  ('Kodak', 'Vision3 250D AHU', 250, 'COLOR', 'ECN-2/C-41'),
  ('Kodak', 'Vision3 500T AHU', 500, 'COLOR', 'ECN-2/C-41'),
  ('Reflx Lab', '100D', 100, 'COLOR', 'ECN-2/C-41'),
  ('Reflx Lab', '320D AHU', 320, 'COLOR', 'ECN-2/C-41'),
  ('Reflx Lab', '640T AHU', 640, 'COLOR', 'ECN-2/C-41'),
  ('Reflx Lab', '400D', 400, 'COLOR', 'C-41'),
  ('Reflx Lab', '800T', 800, 'COLOR', 'C-41'),
  ('Reflx Lab', '50D', 50, 'COLOR', 'ECN-2'),
  ('Reflx Lab', '250D', 250, 'COLOR', 'ECN-2'),
  ('Reflx Lab', '200T', 200, 'COLOR', 'ECN-2'),
  ('Reflx Lab', '500T', 500, 'COLOR', 'ECN-2'),
  ('Reflx Lab', 'Pro 100', 100, 'COLOR', 'C-41'),
  ('Reflx Lab', '100R', 100, 'SLIDE', 'E-6'),
  ('Reflx Lab', 'Pan 400', 400, 'B/W', 'BW'),
  ('Reflx Lab', 'Double X', 250, 'B/W', 'BW')
) v(m, n, i, t, p)
on conflict do nothing;

-- ── El proceso de cada film aprobado (revisado por Diego) ─────────────────
-- «Kodak Ultra» espera a que Diego confirme cuál es; los films sin nombre no
-- se tocan. Gallostill 400D va con su nombre nuevo (se renombró arriba).

update public.film_stocks f
   set process = v.p
  from (values
  ('ADOX', 'CHS 100 II', 'BW'),
  ('ADOX', 'CMS 20 II PRO', 'BW'),
  ('ADOX', 'HR-50', 'BW'),
  ('ADOX', 'Scala 50', 'OTHER'),
  ('Agfa', 'Optima 100', 'C-41'),
  ('Agfa', 'Optima 200', 'C-41'),
  ('Agfa', 'Ultra 100', 'C-41'),
  ('AgfaPhoto', 'APX 100', 'BW'),
  ('AgfaPhoto', 'APX 400', 'BW'),
  ('AgfaPhoto', 'Color 400', 'C-41'),
  ('AgfaPhoto', 'CT Precisa 100', 'E-6'),
  ('AgfaPhoto', 'Vista Plus 200', 'C-41'),
  ('AgfaPhoto', 'Vista Plus 400', 'C-41'),
  ('Bergger', 'Pancro 400', 'BW'),
  ('CatLABS', 'X FILM 100 Color', 'C-41'),
  ('CatLABS', 'X FILM 320', 'BW'),
  ('CatLABS', 'X FILM 320 Pro', 'BW'),
  ('CatLABS', 'X FILM 80', 'BW'),
  ('CineStill', '400D', 'ECN-2/C-41'),
  ('CineStill', '50D', 'ECN-2/C-41'),
  ('CineStill', '800T', 'ECN-2/C-41'),
  ('CineStill', 'bwXX', 'BW'),
  ('CineStill', 'Red Rum', 'C-41'),
  ('Ferrania', 'Orto', 'BW'),
  ('Ferrania', 'P30', 'BW'),
  ('Ferrania', 'P33', 'BW'),
  ('Ferrania', 'Solaris 100', 'C-41'),
  ('Ferrania', 'Solaris 200', 'C-41'),
  ('Ferrania', 'Solaris 400', 'C-41'),
  ('Ferrania', 'Solaris 800', 'C-41'),
  ('Filmdongdong', 'Aerocolor III', 'C-41'),
  ('Flic Film', 'Chrome', 'E-6'),
  ('Flic Film', 'Cine color 250D', 'ECN-2'),
  ('Flic Film', 'Cine color 500T', 'ECN-2'),
  ('Flic Film', 'Cine color 50D', 'ECN-2'),
  ('Flic Film', 'Elektra 100', 'C-41'),
  ('Flic Film', 'UltraPan 100', 'BW'),
  ('Flic Film', 'UltraPan 200', 'BW'),
  ('Flic Film', 'UltraPan 400', 'BW'),
  ('Flic Film', 'Wolfen 100', 'BW'),
  ('Foma', 'Foma Ortho 400', 'BW'),
  ('Foma', 'Fomapan 100 Classic', 'BW'),
  ('Foma', 'Fomapan 200 Creative', 'BW'),
  ('Foma', 'Fomapan 400 Action', 'BW'),
  ('Foma', 'Fomapan R 100', 'OTHER'),
  ('Fujifilm', 'Fuji Press 800', 'C-41'),
  ('Fujifilm', 'Fujicolor 100', 'C-41'),
  ('Fujifilm', 'Fujicolor Industrial 100', 'C-41'),
  ('Fujifilm', 'Fujicolor Industrial 400', 'C-41'),
  ('Fujifilm', 'Fujifilm 200', 'C-41'),
  ('Fujifilm', 'Fujifilm 400', 'C-41'),
  ('Fujifilm', 'Natura 1600', 'C-41'),
  ('Fujifilm', 'Neopan 100 Acros', 'BW'),
  ('Fujifilm', 'Neopan 100 Acros II', 'BW'),
  ('Fujifilm', 'Neopan 1600', 'BW'),
  ('Fujifilm', 'Neopan 400', 'BW'),
  ('Fujifilm', 'Pro 160C', 'C-41'),
  ('Fujifilm', 'Pro 160NS', 'C-41'),
  ('Fujifilm', 'Pro 160S', 'C-41'),
  ('Fujifilm', 'Pro 400H', 'C-41'),
  ('Fujifilm', 'Provia 100F', 'E-6'),
  ('Fujifilm', 'Reala 100', 'C-41'),
  ('Fujifilm', 'Sensia 400', 'E-6'),
  ('Fujifilm', 'Superia 100', 'C-41'),
  ('Fujifilm', 'Superia 1600', 'C-41'),
  ('Fujifilm', 'Superia 200', 'C-41'),
  ('Fujifilm', 'Superia Premium 400', 'C-41'),
  ('Fujifilm', 'Superia X-TRA 400', 'C-41'),
  ('Fujifilm', 'Superia X-TRA 800', 'C-41'),
  ('Fujifilm', 'Velvia 100', 'E-6'),
  ('Fujifilm', 'Velvia 50', 'E-6'),
  ('Gallostill', '800T', 'ECN-2/C-41'),
  ('Harman', 'Phoenix 200', 'C-41'),
  ('Harman', 'Phoenix II 200', 'C-41'),
  ('Harman', 'RED 125', 'C-41'),
  ('Ilford', 'DELTA 100', 'BW'),
  ('Ilford', 'DELTA 3200', 'BW'),
  ('Ilford', 'DELTA 400', 'BW'),
  ('Ilford', 'FP4 Plus', 'BW'),
  ('Ilford', 'HP5 Plus', 'BW'),
  ('Ilford', 'ORTHO Plus', 'BW'),
  ('Ilford', 'PAN 100', 'BW'),
  ('Ilford', 'PAN 400', 'BW'),
  ('Ilford', 'PANF Plus', 'BW'),
  ('Ilford', 'SFX 200', 'BW'),
  ('Ilford', 'XP2 Super', 'C-41'),
  ('Japan Camera Hunter', 'Streetpan 400', 'BW'),
  ('Kentmere', 'PAN 100', 'BW'),
  ('Kentmere', 'PAN 200', 'BW'),
  ('Kentmere', 'PAN 400', 'BW'),
  ('Kodak', 'BW400CN', 'C-41'),
  ('Kodak', 'ColorPlus 200', 'C-41'),
  ('Kodak', 'Double X', 'BW'),
  ('Kodak', 'Double-X', 'BW'),
  ('Kodak', 'Ektachrome E100', 'E-6'),
  ('Kodak', 'Ektachrome E100G', 'E-6'),
  ('Kodak', 'Ektachrome E100VS', 'E-6'),
  ('Kodak', 'Ektachrome E200', 'E-6'),
  ('Kodak', 'Ektar 100', 'C-41'),
  ('Kodak', 'Elite Chrome 100', 'E-6'),
  ('Kodak', 'Elite Chrome 200', 'E-6'),
  ('Gallostill', '400D', 'ECN-2/C-41'),
  ('Kodak', 'Gallostill 800T', 'ECN-2/C-41'),
  ('Kodak', 'Gold 200', 'C-41'),
  ('Kodak', 'Plus-X 125', 'BW'),
  ('Kodak', 'Portra 160', 'C-41'),
  ('Kodak', 'Portra 160NC', 'C-41'),
  ('Kodak', 'Portra 160VC', 'C-41'),
  ('Kodak', 'Portra 400', 'C-41'),
  ('Kodak', 'Portra 400NC', 'C-41'),
  ('Kodak', 'Portra 400UC', 'C-41'),
  ('Kodak', 'Portra 400VC', 'C-41'),
  ('Kodak', 'Portra 800', 'C-41'),
  ('Kodak', 'ProImage 100', 'C-41'),
  ('Kodak', 'T-MAX 100', 'BW'),
  ('Kodak', 'T-MAX 400', 'BW'),
  ('Kodak', 'T-MAX P3200', 'BW'),
  ('Kodak', 'Tri-X', 'BW'),
  ('Kodak', 'UltraMax 400', 'C-41'),
  ('Kodak', 'Verita 200D', 'ECN-2'),
  ('Kodak', 'Vision3 200T', 'ECN-2'),
  ('Kodak', 'Vision3 250D', 'ECN-2'),
  ('Kodak', 'Vision3 500T', 'ECN-2'),
  ('Kodak', 'Vision3 50D', 'ECN-2'),
  ('Konica Minolta', 'Centuria 100', 'C-41'),
  ('Konica Minolta', 'Centuria 200', 'C-41'),
  ('Konica Minolta', 'Centuria 400', 'C-41'),
  ('Konica Minolta', 'Centuria 800', 'C-41'),
  ('Konica Minolta', 'VX 100', 'C-41'),
  ('Konica Minolta', 'VX 200', 'C-41'),
  ('Konica Minolta', 'VX 400', 'C-41'),
  ('Kosmo Foto', 'Agent Shadow', 'BW'),
  ('Kosmo Foto', 'Mono', 'BW'),
  ('Lomography', 'Babylon Kino', 'BW'),
  ('Lomography', 'Berlin 400', 'BW'),
  ('Lomography', 'Color Negative 100', 'C-41'),
  ('Lomography', 'Color Negative 400', 'C-41'),
  ('Lomography', 'Color Negative 800', 'C-41'),
  ('Lomography', 'Earl Grey', 'BW'),
  ('Lomography', 'Fantome Kino', 'BW'),
  ('Lomography', 'Lady Grey', 'BW'),
  ('Lomography', 'LomoChrome Classicolor 200', 'C-41'),
  ('Lomography', 'LomoChrome Color ''92', 'C-41'),
  ('Lomography', 'LomoChrome Metropolis XR', 'C-41'),
  ('Lomography', 'LomoChrome Purple XR', 'C-41'),
  ('Lomography', 'LomoChrome Turquoise XR', 'C-41'),
  ('Lomography', 'Potsdam 100', 'BW'),
  ('Lomography', 'Redscale XR', 'C-41'),
  ('Luckyfilm', 'C200', 'C-41'),
  ('Luckyfilm', 'C400', 'C-41'),
  ('Luckyfilm', 'SHD 100', 'BW'),
  ('Luckyfilm', 'SHD 400', 'BW'),
  ('MARIX', '800T', 'ECN-2/C-41'),
  ('Opticolour', 'Opticolour 200', 'C-41'),
  ('Reto', 'Maple 100', 'C-41'),
  ('Rollei', 'Infrared 400', 'BW'),
  ('Rollei', 'Retro 400S', 'BW'),
  ('Rollei', 'Retro 80S', 'BW'),
  ('Rollei', 'RPX 100', 'BW'),
  ('Rollei', 'RPX 25', 'BW'),
  ('Rollei', 'RPX 400', 'BW'),
  ('Rollei', 'Superpan 200', 'BW'),
  ('Shanghai', 'GP3 100', 'BW')
  ) v(m, n, p)
 where f.status = 'approved'
   and f.process is null
   and app_private.film_stock_key(f.manufacturer, f.name) = app_private.film_stock_key(v.m, v.n);

notify pgrst, 'reload schema';
