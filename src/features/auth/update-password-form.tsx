"use client";

import { type FormEvent, useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

export function UpdatePasswordForm() {
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

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

    const supabase = createBrowserSupabaseClient();
    const { error: updateError } = await supabase.auth.updateUser({ password });

    setBusy(false);

    if (updateError) {
      setError(updateError.message);
      return;
    }

    setMessage("Contraseña actualizada. Ya puedes iniciar sesión.");
  }

  return (
    <form className="auth-card" onSubmit={handleSubmit}>
      <div className="status-label">Nueva contraseña</div>
      <label>
        Password
        <input name="password" type="password" autoComplete="new-password" required />
      </label>
      <label>
        Confirmar password
        <input name="confirm" type="password" autoComplete="new-password" required />
      </label>
      <button className="primary-action" type="submit" disabled={busy}>
        {busy ? "Guardando..." : "Actualizar contraseña"}
      </button>
      {message ? <p className="auth-message auth-message-success">{message}</p> : null}
      {error ? <p className="auth-message auth-message-error">{error}</p> : null}
    </form>
  );
}
