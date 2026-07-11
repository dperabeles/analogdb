"use client";

import { useEffect, useRef, useState } from "react";
import type { EmailOtpType } from "@supabase/supabase-js";
import Link from "next/link";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

type ConfirmState = "checking" | "confirmed" | "invalid" | "nothing";

const ALLOWED_TYPES: EmailOtpType[] = [
  "email",
  "signup",
  "invite",
  "email_change",
];

/**
 * Confirmación de cuenta vía `?token_hash=...&type=email` (plantilla de email
 * con {{ .TokenHash }}). Mismo patrón cross-device que /reset-password: el
 * token se canjea con verifyOtp en ESTE navegador sin importar desde qué
 * cliente se hizo el signup (app móvil, otro navegador) — el flujo PKCE por
 * default fallaría al abrir el enlace fuera del cliente que lo originó.
 */
export function ConfirmAccount() {
  const [state, setState] = useState<ConfirmState>("checking");
  const ran = useRef(false);

  useEffect(() => {
    if (ran.current) return; // el token es de un solo uso: canjear UNA vez
    ran.current = true;

    const params = new URLSearchParams(window.location.search);
    const tokenHash = params.get("token_hash");
    const rawType = params.get("type");

    if (!tokenHash) {
      setState("nothing");
      return;
    }

    const type: EmailOtpType = ALLOWED_TYPES.includes(rawType as EmailOtpType)
      ? (rawType as EmailOtpType)
      : "email";

    const supabase = createBrowserSupabaseClient();
    void supabase.auth
      .verifyOtp({ type, token_hash: tokenHash })
      .then(({ error }) => {
        // token fuera de la URL/historial en cuanto se canjea
        window.history.replaceState(null, "", window.location.pathname);
        setState(error ? "invalid" : "confirmed");
      });
  }, []);

  if (state === "checking") {
    return (
      <div className="auth-card">
        <div className="status-label">Confirmando tu cuenta...</div>
      </div>
    );
  }

  if (state === "confirmed") {
    return (
      <div className="auth-card">
        <div className="status-label">Cuenta confirmada</div>
        <p className="auth-message auth-message-success">
          Tu cuenta de Analog Archive está lista. Vuelve a la app e inicia
          sesión, o entra directo aquí en la web.
        </p>
        <Link className="primary-action" href="/dashboard">
          Ir al dashboard
        </Link>
      </div>
    );
  }

  if (state === "invalid") {
    return (
      <div className="auth-card">
        <div className="status-label">Enlace no válido</div>
        <p className="auth-message auth-message-error">
          El enlace de confirmación no es válido o ya expiró. Intenta iniciar
          sesión — si tu cuenta ya estaba confirmada entrarás normal. Si no
          puedes entrar, escríbenos a hello@analog-archive.com.
        </p>
      </div>
    );
  }

  return (
    <div className="auth-card">
      <div className="status-label">Nada que confirmar</div>
      <p className="auth-message">
        Esta página confirma cuentas nuevas desde el enlace del correo de
        registro. Si ya tienes cuenta, inicia sesión normalmente.
      </p>
    </div>
  );
}
