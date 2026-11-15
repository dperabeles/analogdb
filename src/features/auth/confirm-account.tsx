"use client";

import { useEffect, useRef, useState } from "react";
import type { EmailOtpType } from "@supabase/supabase-js";
import { AccessState } from "@/features/auth/contacto-access";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

type ConfirmState = "checking" | "confirmed" | "invalid" | "nothing";

/// Opens the iPhone app by its URL scheme (Info.plist: analogarchive).
const OPEN_APP = { label: "Abrir Analog Archive", href: "analogarchive://" };

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
      <AccessState
        eyebrow="Acceso / Confirmación"
        title={"Confirmando\ntu correo."}
        plateTitle="Un momento."
        plateNote="Estamos validando el enlace."
        progress
        live
      />
    );
  }

  if (state === "confirmed") {
    return (
      <AccessState
        eyebrow="Acceso / Confirmada"
        title={"Tu cuenta\nestá lista."}
        copy="Tu correo quedó confirmado. Vuelve a la app e inicia sesión."
        plateTitle="Correo confirmado"
        plateNote="Entra con tu correo y tu contraseña."
        primary={OPEN_APP}
        secondary={{ label: "Entrar en la web", href: "/dashboard" }}
        live
      />
    );
  }

  if (state === "invalid") {
    return (
      <AccessState
        eyebrow="Acceso / Enlace"
        title={"Este enlace\nya no sirve."}
        copy="Venció o ya se usó. Entra a la app: si tu correo ya quedó confirmado, pasas; si no, ahí pides otro enlace."
        plateTitle="¿Sigues sin poder entrar?"
        plateNote={
          <>
            Escríbenos a <a href="mailto:hello@analog-archive.com">hello@analog-archive.com</a>
          </>
        }
        primary={OPEN_APP}
        live
      />
    );
  }

  return (
    <AccessState
      eyebrow="Acceso / Confirmación"
      title={"Nada que\nconfirmar."}
      copy="Esta página abre el enlace del correo de registro. Si ya tienes cuenta, inicia sesión en la app."
      primary={OPEN_APP}
    />
  );
}
