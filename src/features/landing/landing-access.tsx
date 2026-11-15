"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import type { AccessLang } from "@/features/auth/access-lang";
import { withLang } from "@/features/auth/access-lang";
import { AccessField, AccessSubmit } from "@/features/auth/contacto-access";
import { buildSignupRequest } from "@/features/auth/signup-identity";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";
import type { LandingCopy } from "./landing-copy";
import styles from "./landing.module.css";

type Mode = "signin" | "signup";
type Notice = { tone: "error" | "ok"; text: string } | null;

/// Sign in and create account, as two tabs with the app's travelling rule.
/// Sign-up sends the page language so the confirmation email matches it.
export function LandingAccess({ copy, lang }: { copy: LandingCopy["access"]; lang: AccessLang }) {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("signin");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<Notice>(null);

  function switchTo(next: Mode) {
    setMode(next);
    setNotice(null);
  }

  async function signIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true);
    setNotice(null);
    const { error } = await createBrowserSupabaseClient().auth.signInWithPassword({
      email: String(form.get("email") || "").trim(),
      password: String(form.get("password") || ""),
    });
    if (error) {
      setBusy(false);
      setNotice({
        tone: "error",
        text:
          error.code === "email_not_confirmed"
            ? copy.notConfirmed
            : error.code === "invalid_credentials"
              ? copy.wrongCredentials
              : copy.failed,
      });
      return;
    }
    router.replace("/dashboard");
    router.refresh();
  }

  async function signUp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const signup = buildSignupRequest(new FormData(event.currentTarget));
    if (!signup.ok) {
      setNotice({ tone: "error", text: signup.error });
      return;
    }
    setBusy(true);
    setNotice(null);
    const request = signup.request;
    const { error } = await createBrowserSupabaseClient().auth.signUp({
      ...request,
      options: { data: { ...request.options.data, locale: lang } },
    });
    setBusy(false);
    if (error) {
      const message = error.message.replace(/^\[[a-z_]+\]\s*/, "");
      setNotice({ tone: "error", text: /\[username_/.test(error.message) ? message : copy.failed });
      return;
    }
    setNotice({ tone: "ok", text: copy.created });
  }

  return (
    <div className={styles.access}>
      <div className={styles.tabs} role="tablist" style={{ ["--n" as string]: 2, ["--i" as string]: mode === "signin" ? 0 : 1 }}>
        {(["signin", "signup"] as const).map((m, i) => (
          <button
            key={m}
            type="button"
            role="tab"
            aria-selected={mode === m}
            className={styles.tab}
            onClick={() => switchTo(m)}
          >
            <span className={styles.tabIndex}>{String(i + 1).padStart(2, "0")}</span>
            {m === "signin" ? copy.signInTab : copy.signUpTab}
          </button>
        ))}
        <span className={styles.tabRule} aria-hidden="true" />
      </div>

      {mode === "signin" ? (
        <form className={styles.accessForm} onSubmit={signIn} noValidate key="signin">
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
      ) : (
        <form className={styles.accessForm} onSubmit={signUp} noValidate key="signup">
          <AccessField
            label={copy.displayName}
            name="displayName"
            type="text"
            minLength={3}
            maxLength={20}
            placeholder={copy.displayNameHint}
            required
          />
          <AccessField
            label={copy.username}
            name="username"
            type="text"
            autoComplete="username"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            placeholder={copy.usernameHint}
            required
          />
          <AccessField label={copy.email} name="email" type="email" autoComplete="email" placeholder={copy.emailHint} required />
          <AccessField label={copy.password} name="password" type="password" autoComplete="new-password" required />
          <AccessSubmit label={busy ? copy.creating : copy.create} disabled={busy} />
        </form>
      )}

      {notice ? (
        <p className={styles.notice} data-tone={notice.tone} role={notice.tone === "error" ? "alert" : "status"}>
          {notice.text}
        </p>
      ) : null}
    </div>
  );
}
