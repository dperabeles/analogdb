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
import { type AccessCopy, ACCESS_COPY } from "@/features/auth/access-copy";
import { type AccessLang, withLang } from "@/features/auth/access-lang";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

/// Supabase answers in English; the person reads their own language.
function recoveryError(
  status: number | undefined,
  code: string | undefined,
  f: AccessCopy["forgot"],
): string {
  if (status === 429 || code === "over_email_send_rate_limit") return f.wait;
  if (code === "validation_failed" || code === "email_address_invalid") return f.incomplete;
  return f.failed;
}

export function PasswordRecoveryForm({ lang }: { lang: AccessLang }) {
  const f = ACCESS_COPY[lang].forgot;
  const back = { label: f.back, href: "/dashboard" };
  const [sentTo, setSentTo] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") || "").trim();

    if (!email.includes("@")) {
      setError(f.incomplete);
      return;
    }

    setBusy(true);
    setError("");

    const redirectTo = `${window.location.origin}${withLang("/reset-password", lang)}`;
    const supabase = createBrowserSupabaseClient();
    const { error: sendError } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo,
    });

    setBusy(false);

    if (sendError) {
      setError(recoveryError(sendError.status, sendError.code, f));
      return;
    }

    setSentTo(email);
  }

  if (sentTo) {
    // Same answer whether or not the address has an account.
    return (
      <AccessState
        eyebrow={f.eyebrow}
        title={f.sentTitle}
        copy={f.sentCopy}
        plateTitle={sentTo}
        plateNote={f.sentNote}
        secondary={back}
        live
      />
    );
  }

  return (
    <section className={accessStyles.state}>
      <AccessHeading eyebrow={f.eyebrow} title={f.formTitle} />
      <form className={accessStyles.form} onSubmit={handleSubmit} noValidate>
        <AccessField
          label={f.email}
          name="email"
          type="email"
          autoComplete="email"
          inputMode="email"
          placeholder={f.emailHint}
          required
        />
        <AccessSubmit label={busy ? f.sending : f.send} disabled={busy} />
        {error ? (
          <p className={accessStyles.error} role="alert">
            {error}
          </p>
        ) : null}
        <AccessLink {...back} />
      </form>
    </section>
  );
}
