#!/usr/bin/env python3
"""Prueba de comportamiento de 20260809000000_admin_actions_hardening.sql.

Corre CONTRA PRODUCCIÓN pero no deja rastro: aplica la migración, suplanta la
sesión de un admin (poniendo `request.jwt.claims` igual que hace PostgREST),
ejerce el flujo completo y termina en ROLLBACK. La cola de pg_net también se
revierte, así que tampoco sale ningún correo.

Es el patrón que faltaba en este repo: hasta ahora no había forma de probar un
cambio de base de datos antes de aplicarlo. Vale la pena reusarlo.

    python3 supabase/tests/admin_actions_hardening_test.py

Requiere el proyecto enlazado (`supabase link`). Desde un worktree, que no
hereda el enlace, apunta a un checkout que sí lo tenga:

    SUPABASE_WORKDIR=/ruta/al/checkout/enlazado \\
      python3 supabase/tests/admin_actions_hardening_test.py

Sale con código 1 si alguna comprobación falla.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
MIGRATION = REPO / "supabase/migrations/20260809000000_admin_actions_hardening.sql"
# El enlace del proyecto (`supabase/.temp/project-ref`) no está versionado, así
# que un worktree no lo hereda. Permite correr la prueba desde uno.
WORKDIR = pathlib.Path(os.environ.get("SUPABASE_WORKDIR", REPO))


def resolve_actors() -> tuple[str, str]:
    """El founder (actor) y cualquier otro usuario real (objetivo).

    El objetivo tiene que existir de verdad: `admin_actions.target_user_id`
    tiene FK contra `auth.users` y un UUID inventado no pasa.
    """
    sql = (
        "select "
        "(select user_id::text from public.user_roles where is_founder limit 1) as founder, "
        "(select p.user_id::text from public.profiles p "
        " where p.user_id <> (select user_id from public.user_roles where is_founder limit 1) "
        " order by p.created_at desc limit 1) as target;"
    )
    out = run_sql(sql)
    row = out["rows"][0]
    if not row.get("founder") or not row.get("target"):
        sys.exit("No encontré un founder y otro usuario con los que probar.")
    return row["founder"], row["target"]


def run_sql(sql: str) -> dict:
    """Ejecuta SQL vía la CLI.

    Se pasa por archivo (`-f`) y no como argumento: un `--` al inicio de un
    comentario lo interpreta como bandera, y el shell se come los `$$` de
    plpgsql.
    """
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as handle:
        handle.write(sql)
        path = handle.name

    proc = subprocess.run(
        ["supabase", "db", "query", "--linked", "-f", path],
        cwd=WORKDIR, capture_output=True, text=True,
    )
    match = re.search(r"\{.*\}", proc.stdout, re.S)
    if not match:
        sys.exit(
            f"La consulta falló (código {proc.returncode}).\n"
            f"STDOUT: {proc.stdout[:800]}\nSTDERR: {proc.stderr[:1500]}"
        )
    return json.loads(match.group(0))


def build_probe(founder: str, target: str) -> str:
    body = MIGRATION.read_text().rstrip()
    if not body.endswith("commit;"):
        sys.exit("La migración no termina en commit; — revisa el archivo.")
    return body[: -len("commit;")] + f"""
set local request.jwt.claims = '{{"sub":"{founder}","role":"authenticated"}}';

create temporary table _resultados (paso text, ok boolean, detalle text) on commit drop;

do $test$
declare
  a public.admin_actions;
  b public.admin_actions;
  n integer;
begin
  insert into _resultados values ('la sesión suplantada se resuelve',
    auth.uid() = '{founder}', coalesce(auth.uid()::text, 'NULL'));

  a := public.request_admin_action('promote_to_admin', '{target}', '  probando  ');
  insert into _resultados values ('propone y guarda el motivo sin espacios',
    a.request_reason = 'probando', coalesce(a.request_reason, 'NULL'));
  insert into _resultados values ('nace pending', a.status = 'pending', a.status);
  insert into _resultados values ('trae caducidad de ~30 días',
    a.expires_at between now() + interval '29 days' and now() + interval '31 days',
    coalesce(a.expires_at::text, 'NULL'));

  b := public.request_admin_action('promote_to_admin', '{target}', 'otro motivo');
  insert into _resultados values ('proponer dos veces no duplica', b.id = a.id, b.id::text);
  select count(*) into n from public.admin_actions where target_user_id = '{target}';
  insert into _resultados values ('sigue habiendo una sola fila', n = 1, n::text);

  b := public.cancel_admin_action(a.id, null);
  insert into _resultados values ('cancelar deja cancelled', b.status = 'cancelled', b.status);
  insert into _resultados values ('el motivo por defecto es correcto',
    b.resolved_reason = 'Cancelled by requester', coalesce(b.resolved_reason, 'NULL'));
  insert into _resultados values ('cancelar sella resolved_at',
    b.resolved_at is not null, coalesce(b.resolved_at::text, 'NULL'));

  b := public.cancel_admin_action(a.id, 'otra vez');
  insert into _resultados values ('cancelar dos veces no falla', b.status = 'cancelled', b.status);

  b := public.request_admin_action('promote_to_admin', '{target}', 'de nuevo');
  insert into _resultados values ('tras cancelar se puede volver a proponer',
    b.id <> a.id, b.id::text);

  update public.admin_actions set expires_at = now() - interval '1 day' where id = b.id;
  b := public.cast_admin_action_vote(b.id, 'approved');
  insert into _resultados values ('una propuesta vencida se auto-cancela',
    b.status = 'cancelled', b.status);
  insert into _resultados values ('deja constancia de la caducidad',
    b.resolved_reason = 'Expired without unanimous approval',
    coalesce(b.resolved_reason, 'NULL'));
  -- Se cuentan filas de ADMIN: el usuario ya tiene una con role='user', así
  -- que contar cualquier fila daría 1 siempre y no comprobaría nada.
  select count(*) into n from public.user_roles
    where user_id = '{target}' and role = 'admin';
  insert into _resultados values ('la vencida NO otorgó admin', n = 0, n::text);

  begin
    b := public.request_admin_action('promote_to_admin', '{founder}', null);
    insert into _resultados values ('sigue bloqueando cambiarse el rol a sí mismo',
      false, 'NO lanzó excepción');
  exception when others then
    insert into _resultados values ('sigue bloqueando cambiarse el rol a sí mismo',
      sqlerrm like '%self role changes%', sqlerrm);
  end;

  b := public.request_admin_action('promote_to_admin', '{target}', 'camino feliz');
  b := public.cast_admin_action_vote(b.id, 'approved');
  insert into _resultados values ('con un solo admin la unanimidad ejecuta',
    b.status = 'executed', b.status);
  select count(*) into n from public.user_roles
    where user_id = '{target}' and role = 'admin';
  insert into _resultados values ('el rol se otorgó', n = 1, n::text);
end
$test$;

select paso, ok, detalle from _resultados order by 1;

rollback;
"""


def main() -> int:
    founder, target = resolve_actors()
    print(f"actor:    {founder} (founder)")
    print(f"objetivo: {target}\n")

    filas = run_sql(build_probe(founder, target)).get("rows", [])
    fallos = 0
    for fila in filas:
        if not fila["ok"]:
            fallos += 1
        print(f"  {'✓' if fila['ok'] else '✗'} {fila['paso']}  →  {fila['detalle']}")

    print(f"\n{len(filas)} comprobaciones, {fallos} fallidas")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
