"use client";

import { type FormEvent, useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

export function PasswordRecoveryForm() {
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") || "").trim();

    setBusy(true);
    setError("");
    setMessage("");

    const redirectTo = `${window.location.origin}/reset-password`;
    const supabase = createBrowserSupabaseClient();
    const { error: recoveryError } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo
    });

    setBusy(false);

    if (recoveryError) {
      setError(recoveryError.message);
      return;
    }

    setMessage("Revisa tu correo para continuar el restablecimiento.");
  }

  return (
    <form className="auth-card" onSubmit={handleSubmit}>
      <div className="status-label">Recuperar contraseña</div>
      <label>
        Correo
        <input name="email" type="email" autoComplete="email" required />
      </label>
      <button className="primary-action" type="submit" disabled={busy}>
        {busy ? "Enviando..." : "Enviar enlace"}
      </button>
      {message ? <p className="auth-message auth-message-success">{message}</p> : null}
      {error ? <p className="auth-message auth-message-error">{error}</p> : null}
    </form>
  );
}
