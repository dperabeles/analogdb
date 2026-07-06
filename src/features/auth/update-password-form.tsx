"use client";

import { type FormEvent, useEffect, useRef, useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

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
export function UpdatePasswordForm() {
  const [recovery, setRecovery] = useState<RecoveryState>("checking");
  const [message, setMessage] = useState("");
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
        window.history.replaceState(null, "", window.location.pathname);
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
      setError("La contraseña debe tener al menos 6 caracteres.");
      return;
    }

    if (password !== confirm) {
      setError("Las contraseñas no coinciden.");
      return;
    }

    setBusy(true);
    setError("");
    setMessage("");

    const { error: updateError } = await getSupabase().auth.updateUser({
      password,
    });

    setBusy(false);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setMessage("Contraseña actualizada. Ya puedes iniciar sesión.");
  }

  if (recovery === "invalid") {
    return (
      <div className="auth-card">
        <div className="status-label">Enlace no válido</div>
        <p className="auth-message auth-message-error">
          El enlace de recuperación no es válido o ya expiró. Pide uno nuevo
          para continuar.
        </p>
        <a className="primary-action" href="/forgot-password">
          Pedir nuevo enlace
        </a>
      </div>
    );
  }

  return (
    <form className="auth-card" onSubmit={handleSubmit}>
      <div className="status-label">Nueva contraseña</div>
      <label>
        Password
        <input
          name="password"
          type="password"
          autoComplete="new-password"
          disabled={recovery !== "ready"}
          required
        />
      </label>
      <label>
        Confirmar password
        <input
          name="confirm"
          type="password"
          autoComplete="new-password"
          disabled={recovery !== "ready"}
          required
        />
      </label>
      <button
        className="primary-action"
        type="submit"
        disabled={busy || recovery !== "ready"}
      >
        {recovery === "checking"
          ? "Verificando enlace..."
          : busy
            ? "Guardando..."
            : "Actualizar contraseña"}
      </button>
      {message ? (
        <p className="auth-message auth-message-success">{message}</p>
      ) : null}
      {error ? <p className="auth-message auth-message-error">{error}</p> : null}
    </form>
  );
}
