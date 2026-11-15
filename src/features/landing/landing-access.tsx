"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import type { AccessLang } from "@/features/auth/access-lang";
import { withLang } from "@/features/auth/access-lang";
import { AccessField, AccessSubmit } from "@/features/auth/contacto-access";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";
import type { LandingCopy } from "./landing-copy";
import styles from "./landing.module.css";

/// Sign in, for the web while it lasts. Accounts are created in the app
/// (DEC-013: the web becomes the home page), so the second half is the
/// app's plate instead of a sign-up form.
export function LandingAccess({
  copy,
  platform,
  platformNote,
  lang,
}: {
  copy: LandingCopy["access"];
  platform: string;
  platformNote: string;
  lang: AccessLang;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true);
    setError("");
    const { error: signInError } = await createBrowserSupabaseClient().auth.signInWithPassword({
      email: String(form.get("email") || "").trim(),
      password: String(form.get("password") || ""),
    });
    if (signInError) {
      setBusy(false);
      setError(
        signInError.code === "email_not_confirmed"
          ? copy.notConfirmed
          : signInError.code === "invalid_credentials"
            ? copy.wrongCredentials
            : copy.failed,
      );
      return;
    }
    router.replace("/dashboard");
    router.refresh();
  }

  return (
    <div className={styles.access}>
      <form className={styles.accessForm} onSubmit={signIn} noValidate>
        <AccessField label={copy.email} name="email" type="email" autoComplete="email" placeholder={copy.emailHint} required />
        <AccessField
          label={copy.password}
          name="password"
          type="password"
          autoComplete="current-password"
          placeholder={copy.passwordHint}
          required
        />
        <AccessSubmit label={busy ? copy.entering : copy.enter} disabled={busy} />
        <a className={styles.quietLink} href={withLang("/forgot-password", lang)}>
          {copy.forgot}
        </a>
      </form>

      {error ? (
        <p className={styles.notice} data-tone="error" role="alert">
          {error}
        </p>
      ) : null}

      <div className={styles.signUpApp}>
        <span className={styles.signUpPrompt}>{copy.newHere}</span>
        <div className={styles.miniPlate}>
          <span className={styles.miniPlateNo} aria-hidden="true">
            02
          </span>
          <div>
            <div className={styles.plateTitle}>
              {copy.signUpInApp} · {platform}
            </div>
            <div className={styles.plateNote}>{platformNote}</div>
          </div>
        </div>
      </div>
    </div>
  );
}
