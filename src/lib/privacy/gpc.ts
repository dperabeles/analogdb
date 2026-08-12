import type { NextRequest, NextResponse } from "next/server";

/// Global Privacy Control (ANA-31).
///
/// GPC es una señal que el navegador manda —cabecera `Sec-GPC: 1`— cuando la
/// persona activó "no vendan ni compartan mis datos". CCPA/CPRA y varias leyes
/// estatales de EE. UU. obligan a **honrarla**, no solo a ofrecer un botón.
///
/// ── Qué significa honrarla aquí ───────────────────────────────────────────
///
/// Analog Archive **no vende ni comparte datos para publicidad cross-context**
/// (Privacy Policy §3 y §11.2). Así que la obligación de fondo ya se cumple
/// para todo el mundo, mande o no la señal.
///
/// Lo que este módulo añade es lo que faltaba: **constancia y respeto
/// operativo**. Se detecta la señal, se deja en una cookie legible por el
/// resto de la app, y se devuelve en una cabecera de respuesta para que quede
/// registro de que se recibió.
///
/// ── Por qué importa aunque hoy sea casi un no-op ──────────────────────────
///
/// El día que entre analítica (ANA-61) o cualquier píxel, `gpcOptOut()` ya
/// está ahí para consultarse. Si esto no existiera, ese día habría que
/// acordarse de añadirlo — y es exactamente el tipo de cosa de la que nadie
/// se acuerda.

/// Cabecera estándar del navegador.
const GPC_HEADER = "sec-gpc";

/// Cookie propia para que Server Components y la app puedan leer la
/// preferencia sin volver a mirar cabeceras.
export const GPC_COOKIE = "aa_gpc";

/// Cabecera de respuesta: deja constancia de que la señal se recibió y se
/// respetó. Es lo que un auditor mira.
const GPC_ACK_HEADER = "x-aa-gpc-honored";

/// ¿La petición trae la señal activada?
///
/// La especificación define `Sec-GPC: 1` como único valor afirmativo. Se
/// compara con eso y no con "cualquier valor presente": un `Sec-GPC: 0`
/// significa lo contrario y tratarlo como opt-out sería igual de incorrecto.
export function hasGpcSignal(request: NextRequest): boolean {
  return request.headers.get(GPC_HEADER)?.trim() === "1";
}

/// Aplica la señal a la respuesta: cookie + acuse.
///
/// La cookie NO es httpOnly a propósito — el cliente tiene que poder leerla
/// para decidir si carga algo. Y no lleva datos personales: es un `1`.
export function applyGpc(request: NextRequest, response: NextResponse): NextResponse {
  if (!hasGpcSignal(request)) return response;

  response.cookies.set(GPC_COOKIE, "1", {
    path: "/",
    sameSite: "lax",
    httpOnly: false,
    secure: process.env.NODE_ENV === "production",
    maxAge: 60 * 60 * 24 * 365
  });
  response.headers.set(GPC_ACK_HEADER, "1");

  return response;
}

/// ¿Hay que tratar a esta persona como opt-out?
///
/// Para usar desde Server Components y desde cualquier futura integración de
/// analítica. Mira la señal en vivo y, si no viene, la cookie recordada.
export function gpcOptOut(request: NextRequest): boolean {
  return hasGpcSignal(request) || request.cookies.get(GPC_COOKIE)?.value === "1";
}
