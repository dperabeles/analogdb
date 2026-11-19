"use client";

import { useEffect, useRef, useState } from "react";
import type { EmailOtpType } from "@supabase/supabase-js";
import { ACCESS_COPY } from "@/features/auth/access-copy";
import { type AccessLang, withLang } from "@/features/auth/access-lang";
import { AccessState } from "@/features/auth/contacto-access";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

type ConfirmState = "checking" | "confirmed" | "invalid" | "nothing";

/// Opens the iPhone app by its URL scheme (Info.plist: analogarchive).
const APP_URL = "analogarchive://";

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
export function ConfirmAccount({ lang }: { lang: AccessLang }) {
  const t = ACCESS_COPY[lang];
  const c = t.confirm;
  const openApp = { label: t.openApp, href: APP_URL };
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
        window.history.replaceState(null, "", withLang(window.location.pathname, lang));
        setState(error ? "invalid" : "confirmed");
      });
  }, []);

  if (state === "checking") {
    return (
      <AccessState
        eyebrow={c.checkingEyebrow}
        title={c.checkingTitle}
        plateTitle={t.oneMoment}
        plateNote={c.checkingNote}
        progress
        live
      />
    );
  }

  if (state === "confirmed") {
    return (
      <AccessState
        eyebrow={c.doneEyebrow}
        title={c.doneTitle}
        copy={c.doneCopy}
        plateTitle={c.donePlate}
        plateNote={c.doneNote}
        primary={openApp}
        live
      />
    );
  }

  if (state === "invalid") {
    return (
      <AccessState
        eyebrow={c.invalidEyebrow}
        title={c.invalidTitle}
        copy={c.invalidCopy}
        plateTitle={t.stillStuck}
        plateNote={
          <>
            {t.support} <a href="mailto:hello@analog-archive.com">hello@analog-archive.com</a>
          </>
        }
        primary={openApp}
        live
      />
    );
  }

  return (
    <AccessState
      eyebrow={c.checkingEyebrow}
      title={c.nothingTitle}
      copy={c.nothingCopy}
      primary={openApp}
    />
  );
}
