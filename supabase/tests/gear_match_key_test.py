#!/usr/bin/env python3
"""Ensaya match_key dentro de un ROLLBACK, incluyendo los caminos de escritura
reales de los DOS clientes: el insert plano de la app y el upsert de la web."""
import subprocess, pathlib, tempfile, json, re, sys

import os
REPO = pathlib.Path(os.environ.get("SUPABASE_WORKDIR",
                                   pathlib.Path(__file__).resolve().parents[2]))
MIG = pathlib.Path(__file__).resolve().parents[1] / "migrations/20260811120000_gear_match_key.sql"

body = MIG.read_text().rstrip()
assert body.endswith("commit;")
cuerpo = body[body.index("begin;") + len("begin;"):-len("commit;")]

probe = """
create temporary table _antes as select id, maker, model, mount from public.cameras;
create temporary table _antes_l as select id, maker, model, mount from public.lenses;
create temporary table _rollos_antes as select id, camera_id from public.rolls;
""" + cuerpo + """
create temporary table _r (paso text, ok boolean, detalle text) on commit drop;
do $t$
declare n integer; d text; owner uuid;
begin
  select owner_user_id into owner from public.cameras limit 1;

  -- Nada se perdió ni se movió
  insert into _r values ('siguen 125 cámaras y 16 lentes',
    (select count(*) from public.cameras) = 125 and (select count(*) from public.lenses) = 16,
    (select count(*) from public.cameras)::text || ' / ' || (select count(*) from public.lenses)::text);
  select count(*) into n from public.cameras c join _antes a on a.id=c.id
    where c.maker is distinct from a.maker or c.model is distinct from a.model;
  insert into _r values ('el relleno no cambió ninguna marca ni modelo', n = 0, n::text);
  select count(*) into n from public.rolls r join _rollos_antes a on a.id=r.id
    where r.camera_id is distinct from a.camera_id;
  insert into _r values ('ningún rollo se movió', n = 0, n::text);

  -- match_key quedó puesto en todo
  select count(*) into n from public.cameras where match_key is null or match_key = '|';
  insert into _r values ('toda cámara tiene match_key', n = 0, n::text);
  select count(*) into n from public.lenses where match_key is null;
  insert into _r values ('todo lente tiene match_key', n = 0, n::text);

  -- CAMINO DE LA APP MÓVIL: insert plano. Debe normalizar el casing solo.
  insert into public.cameras (owner_user_id, maker, model, format, type)
    values (owner, 'pEnTaX', 'Prueba MK', '35mm', 'SLR');
  select maker into d from public.cameras where model = 'Prueba MK';
  insert into _r values ('insert de la app: el casing se normaliza solo', d = 'Pentax', d);
  select match_key into d from public.cameras where model = 'Prueba MK';
  insert into _r values ('insert de la app: match_key se calcula solo', d = 'pentax|prueba mk', d);

  -- La única nueva atrapa el duplicado que la vieja NO veía (espacios de más)
  begin
    insert into public.cameras (owner_user_id, maker, model, format, type)
      values (owner, 'Pentax', 'Prueba  MK', '35mm', 'SLR');
    insert into _r values ('la única nueva bloquea el duplicado por espacios', false, 'NO lo bloqueó');
  exception when unique_violation then
    insert into _r values ('la única nueva bloquea el duplicado por espacios', true, 'unique_violation');
  end;

  -- CAMINO DE LA WEB: upsert con onConflict sobre la única VIEJA. Debe seguir
  -- funcionando; si esto falla, el alta de equipo en la web queda rota.
  insert into public.cameras (owner_user_id, maker, model, format, type)
    values (owner, 'Pentax', 'Prueba MK', '35mm', 'TLR')
    on conflict (owner_user_id, maker, model) do update set type = excluded.type;
  select type into d from public.cameras where model = 'Prueba MK';
  insert into _r values ('el upsert de la web sigue funcionando', d = 'TLR', coalesce(d,'NULL'));
  select count(*) into n from public.cameras where model = 'Prueba MK';
  insert into _r values ('el upsert actualizó en vez de duplicar', n = 1, n::text);

  -- Una EDICIÓN también renormaliza
  update public.cameras set maker = 'CANON' where model = 'Prueba MK';
  select maker || ' / ' || match_key into d from public.cameras where model = 'Prueba MK';
  insert into _r values ('editar también renormaliza y recalcula', d = 'Canon / canon|prueba mk', d);
end $t$;
select paso, ok, detalle from _r order by 1;
rollback;
"""
with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
    f.write(probe); path = f.name
r = subprocess.run(["supabase","db","query","--linked","-f",path], cwd=REPO, capture_output=True, text=True)
m = re.search(r"\{.*\}", r.stdout, re.S)
if not m:
    print(f"[{r.returncode}]\n{r.stdout[:600]}\n{r.stderr[:1800]}"); sys.exit(1)
filas = json.loads(m.group(0))["rows"]; fallos = 0
for f_ in filas:
    if not f_["ok"]: fallos += 1
    print(f"  {'✓' if f_['ok'] else '✗'} {f_['paso']}  →  {f_['detalle']}")
print(f"\n{len(filas)} comprobaciones, {fallos} fallidas")
sys.exit(1 if fallos else 0)
