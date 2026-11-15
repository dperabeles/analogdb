"use client";

import { type FormEvent, useEffect, useRef, useState } from "react";
import {
  AccessField,
  AccessHeading,
  AccessState,
  AccessSubmit,
  accessStyles,
} from "@/features/auth/contacto-access";
import { type AccessCopy, ACCESS_COPY } from "@/features/auth/access-copy";
import { type AccessLang, withLang } from "@/features/auth/access-lang";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

/// Opens the iPhone app by its URL scheme (Info.plist: analogarchive).
const APP_URL = "analogarchive://";

/// Supabase answers in English; the person reads their own language.
function passwordError(code: string | undefined, r: AccessCopy["reset"]): string {
  if (code === "same_password") return r.samePassword;
  if (code === "weak_password") return r.weakPassword;
  return r.failed;
}

type RecoveryState = "checking" | "ready" | "invalid";

/**
 * El enlace del correo de recovery trae `?token_hash=...&type=recovery`
 * (plantilla de email con {{ .TokenHash }}). Canjearlo con verifyOtp establece
 * la sesión en ESTE navegador sin importar desde qué cliente se pidió el
 * reset (app móvil, otro navegador, etc.) — a diferencia del flujo PKCE
 * (?code=...), que solo funciona en el mismo cliente que lo inició y por eso
 * fallaba con "Auth session missing!" al pedir el reset desde la app.
 *
 * Se mantiene compatibilidad con enlaces legacy en vuelo (tokens en el
 * fragmento hash del flujo implícito, o ?code= del mismo navegador):
 * supabase-js los procesa solo vía detectSessionInUrl y lo detectamos con
 * getSession/onAuthStateChange.
 */
export function UpdatePasswordForm({ lang }: { lang: AccessLang }) {
  const t = ACCESS_COPY[lang];
  const r = t.reset;
  const [recovery, setRecovery] = useState<RecoveryState>("checking");
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const supabaseRef =
    useRef<ReturnType<typeof createBrowserSupabaseClient> | null>(null);

  function getSupabase() {
    if (!supabaseRef.current) {
      supabaseRef.current = createBrowserSupabaseClient();
    }
    return supabaseRef.current;
  }

  useEffect(() => {
    const supabase = getSupabase();
    let cancelled = false;

    // Los flujos legacy establecen sesión de forma asíncrona al cargar la
    // página; este listener avisa cuando eso ocurre.
    const { data: subscription } = supabase.auth.onAuthStateChange((event) => {
      if (cancelled) return;
      if (event === "PASSWORD_RECOVERY" || event === "SIGNED_IN") {
        setRecovery("ready");
      }
    });

    async function establishSession() {
      const params = new URLSearchParams(window.location.search);
      const tokenHash = params.get("token_hash");
      const type = params.get("type");

      if (tokenHash && type === "recovery") {
        const { error: verifyError } = await supabase.auth.verifyOtp({
          type: "recovery",
          token_hash: tokenHash,
        });
        if (cancelled) return;
        // El token es de un solo uso: fuera de la URL/historial.
        window.history.replaceState(null, "", withLang(window.location.pathname, lang));
        setRecovery(verifyError ? "invalid" : "ready");
        return;
      }

      // Sin token_hash: dar un momento a detectSessionInUrl (hash implícito o
      // ?code= del mismo navegador) y revisar si dejó sesión.
      const { data } = await supabase.auth.getSession();
      if (cancelled) return;
      if (data.session) {
        setRecovery("ready");
      } else {
        // Espera corta por si el intercambio asíncrono sigue en curso; el
        // onAuthStateChange de arriba nos saca de "checking" si llega tarde.
        window.setTimeout(() => {
          if (!cancelled) {
            setRecovery((current) =>
              current === "checking" ? "invalid" : current
            );
          }
        }, 1500);
      }
    }

    void establishSession();

    return () => {
      cancelled = true;
      subscription.subscription.unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const password = String(form.get("password") || "");
    const confirm = String(form.get("confirm") || "");

    if (password.length < 6) {
      setError(r.tooShort);
      return;
    }

    if (password !== confirm) {
      setError(r.mismatch);
      return;
    }

    setBusy(true);
    setError("");

    const { error: updateError } = await getSupabase().auth.updateUser({
      password,
    });

    setBusy(false);

    if (updateError) {
      setError(passwordError(updateError.code, r));
      return;
    }

    setSaved(true);
  }

  if (recovery === "invalid") {
    return (
      <AccessState
        eyebrow={r.eyebrow}
        title={r.invalidTitle}
        copy={r.invalidCopy}
        plateTitle={t.stillStuck}
        plateNote={
          <>
            {t.support} <a href="mailto:hello@analog-archive.com">hello@analog-archive.com</a>
          </>
        }
        primary={{ label: r.askAgain, href: withLang("/forgot-password", lang) }}
        live
      />
    );
  }

  if (recovery === "checking") {
    return (
      <AccessState
        eyebrow={r.eyebrow}
        title={r.checkingTitle}
        plateTitle={t.oneMoment}
        plateNote={r.checkingNote}
        progress
        live
      />
    );
  }

  if (saved) {
    return (
      <AccessState
        eyebrow={r.eyebrow}
        title={r.savedTitle}
        copy={r.savedCopy}
        plateTitle={r.savedPlate}
        plateNote={r.savedNote}
        primary={{ label: t.openApp, href: APP_URL }}
        secondary={{ label: t.web, href: "/dashboard" }}
        live
      />
    );
  }

  return (
    <section className={accessStyles.state}>
      <AccessHeading eyebrow={r.eyebrow} title={r.formTitle} />
      <form className={accessStyles.form} onSubmit={handleSubmit} noValidate>
        <AccessField
          label={r.password}
          name="password"
          type="password"
          autoComplete="new-password"
          required
        />
        <AccessField
          label={r.repeat}
          name="confirm"
          type="password"
          autoComplete="new-password"
          required
        />
        <AccessSubmit label={busy ? r.saving : r.save} disabled={busy} />
        {error ? (
          <p className={accessStyles.error} role="alert">
            {error}
          </p>
        ) : null}
      </form>
    </section>
  );
}
