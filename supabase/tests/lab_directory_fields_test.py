#!/usr/bin/env python3
"""Ensaya los campos del directorio dentro de un ROLLBACK."""
import subprocess, pathlib, tempfile, json, re, sys
import os
REPO = pathlib.Path(os.environ.get("SUPABASE_WORKDIR",
                                   pathlib.Path(__file__).resolve().parents[2]))
MIG = pathlib.Path(__file__).resolve().parents[1] / "migrations/20260813100000_lab_directory_fields.sql"

body = MIG.read_text().rstrip()
cuerpo = body[body.index("begin;")+len("begin;"):-len("commit;")]
probe = """
create temporary table _antes as select id, name, city, instagram from public.labs;
""" + cuerpo + """
create temporary table _r (prueba text, ok boolean, detalle text) on commit drop;
do $t$
declare n integer;
begin
  select count(*) into n from public.labs;
  insert into _r values ('siguen 34 labs', n = 34, n::text);

  select count(*) into n from public.labs l join _antes a on a.id=l.id
   where l.name is distinct from a.name or l.city is distinct from a.city
      or l.instagram is distinct from a.instagram;
  insert into _r values ('ningun dato existente cambio', n = 0, n::text);

  select count(*) into n from public.labs
   where services <> '{}' or formats <> '{}' or accepts_mail;
  insert into _r values ('los campos nuevos arrancan vacios', n = 0, n::text);

  -- El vocabulario cerrado tiene que RECHAZAR lo que no esta en la lista.
  begin
    update public.labs set services = array['color'] where id = (select min(id) from public.labs);
    insert into _r values ('rechaza un servicio inventado', false, 'lo acepto!');
  exception when check_violation then
    insert into _r values ('rechaza un servicio inventado', true, 'check_violation');
  end;

  begin
    update public.labs set formats = array['6x6'] where id = (select min(id) from public.labs);
    insert into _r values ('rechaza un formato inventado', false, 'lo acepto!');
  exception when check_violation then
    insert into _r values ('rechaza un formato inventado', true, 'check_violation');
  end;

  -- Y ACEPTAR los validos, incluida una combinacion.
  update public.labs set services = array['c41','bw','scan'], formats = array['35mm','120'],
         accepts_mail = true, address = 'Calle 1', website = 'https://x.com'
   where id = (select min(id) from public.labs);
  select count(*) into n from public.labs
   where services @> array['c41'] and formats @> array['120'] and accepts_mail;
  insert into _r values ('acepta una combinacion valida', n = 1, n::text);
end $t$;
select prueba, ok, detalle from _r order by 1;
rollback;
"""
with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
    f.write(probe); path = f.name
r = subprocess.run(["supabase","db","query","--linked","-f",path], cwd=REPO, capture_output=True, text=True)
m = re.search(r"\{.*\}", r.stdout, re.S)
if not m:
    print(f"[{r.returncode}]\n{r.stdout[:500]}\n{r.stderr[:1500]}"); sys.exit(1)
filas = json.loads(m.group(0))["rows"]; f_ = 0
for x in filas:
    if not x["ok"]: f_ += 1
    print(f"  {'✓' if x['ok'] else '✗'} {x['prueba']}  →  {x['detalle']}")
print(f"\n{len(filas)} comprobaciones, {f_} fallidas")
sys.exit(1 if f_ else 0)
