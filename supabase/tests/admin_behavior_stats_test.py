#!/usr/bin/env python3
"""Ensaya admin_behavior_stats en un ROLLBACK y enseña lo que devolvería."""
import subprocess, pathlib, tempfile, json, re, sys

import os
REPO = pathlib.Path(os.environ.get("SUPABASE_WORKDIR",
                                   pathlib.Path(__file__).resolve().parents[2]))
MIG = pathlib.Path(__file__).resolve().parents[1] / "migrations/20260812100000_admin_behavior_stats.sql"

def q(sql):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql); path = f.name
    return subprocess.run(["supabase","db","query","--linked","-f",path],
                          cwd=REPO, capture_output=True, text=True)

r = q("select user_id::text as founder from public.user_roles where is_founder limit 1;")
FOUNDER = json.loads(re.search(r"\{.*\}", r.stdout, re.S).group(0))["rows"][0]["founder"]

body = MIG.read_text().rstrip()
cuerpo = body[body.index("begin;")+len("begin;"):-len("commit;")]

probe = cuerpo + f"""
set local request.jwt.claims = '{{"sub":"{FOUNDER}","role":"authenticated"}}';
select public.admin_behavior_stats() as m;
rollback;
"""
r = q(probe)
m = re.search(r"\{.*\}", r.stdout, re.S)
if not m:
    print(f"[{r.returncode}]\n{r.stdout[:500]}\n{r.stderr[:1500]}"); sys.exit(1)
filas = json.loads(m.group(0))["rows"]
if not filas:
    print("sin filas"); sys.exit(1)
d = filas[0]["m"]
if isinstance(d, str): d = json.loads(d)

print("MÉTRICAS QUE DEVUELVE (datos reales de producción)\n")
orden = [("users_total","usuarios totales"),("users_with_rolls","con al menos un rollo"),
         ("never_started","NUNCA cargaron un rollo"),("active_7d","activos 7d"),
         ("active_30d","activos 30d"),("signups_7d","altas 7d"),("signups_30d","altas 30d"),
         ("rolls_7d","rollos 7d"),("rolls_30d","rollos 30d"),("rolls_total","rollos totales"),
         ("cohort_30d","cohorte de 30+ días"),("retained_30d","de esos, siguen activos"),
         ("median_rolls","mediana de rollos/usuario"),("max_rolls","máximo de un usuario"),
         ("rolls_with_frames","rollos con fotogramas"),("rolls_with_lab","rollos con lab")]
for k, etiqueta in orden:
    print(f"  {etiqueta:28} {d.get(k)}")
w = d.get("weekly", [])
print(f"\n  serie semanal: {len(w)} semanas")
print("   ", " ".join(str(x["rolls"]) for x in w))
faltan = [k for k,_ in orden if k not in d]
print(f"\n{'✓ todas las claves presentes' if not faltan else '✗ faltan: '+str(faltan)}")
sys.exit(1 if faltan else 0)
