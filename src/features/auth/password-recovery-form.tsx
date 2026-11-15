"use client";

import { type FormEvent, useState } from "react";
import {
  AccessField,
  AccessHeading,
  AccessLink,
  AccessState,
  AccessSubmit,
  accessStyles,
} from "@/features/auth/contacto-access";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

const BACK = { label: "Volver a entrar", href: "/dashboard" };

/// Supabase answers in English; the person reads Spanish.
function recoveryError(status: number | undefined, code: string | undefined): string {
  if (status === 429 || code === "over_email_send_rate_limit") {
    return "Espera un minuto antes de pedir otro correo.";
  }
  if (code === "validation_failed" || code === "email_address_invalid") {
    return "Revisa el correo; parece incompleto.";
  }
  return "No pudimos enviar el correo. Inténtalo de nuevo.";
}

export function PasswordRecoveryForm() {
  const [sentTo, setSentTo] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") || "").trim();

    if (!email.includes("@")) {
      setError("Revisa el correo; parece incompleto.");
      return;
    }

    setBusy(true);
    setError("");

    const redirectTo = `${window.location.origin}/reset-password`;
    const supabase = createBrowserSupabaseClient();
    const { error: sendError } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo,
    });

    setBusy(false);

    if (sendError) {
      setError(recoveryError(sendError.status, sendError.code));
      return;
    }

    setSentTo(email);
  }

  if (sentTo) {
    // Same answer whether or not the address has an account.
    return (
      <AccessState
        eyebrow="Acceso / Recuperación"
        title={"Revisa\ntu correo."}
        copy="Si hay una cuenta con ese correo, te llegará un enlace para elegir una contraseña nueva."
        plateTitle={sentTo}
        plateNote="El enlace vence en una hora. Si no aparece, revisa el correo no deseado."
        secondary={BACK}
        live
      />
    );
  }

  return (
    <section className={accessStyles.state}>
      <AccessHeading eyebrow="Acceso / Recuperación" title={"Recupera\ntu acceso."} />
      <form className={accessStyles.form} onSubmit={handleSubmit} noValidate>
        <AccessField
          label="Correo"
          name="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          placeholder="tu@correo.com"
          required
        />
        <AccessSubmit label={busy ? "Enviando…" : "Enviar enlace"} disabled={busy} />
        {error ? (
          <p className={accessStyles.error} role="alert">
            {error}
          </p>
        ) : null}
        <AccessLink {...BACK} />
      </form>
    </section>
  );
}
