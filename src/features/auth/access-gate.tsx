"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { type FormEvent, useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

type Message = {
  tone: "neutral" | "error" | "success";
  text: string;
};

export function AccessGate() {
  const router = useRouter();
  const [message, setMessage] = useState<Message>({
    tone: "neutral",
    text: ""
  });
  const [busy, setBusy] = useState<"login" | "signup" | null>(null);

  async function handleLogin(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email") || "").trim();
    const password = String(form.get("password") || "");

    setBusy("login");
    setMessage({ tone: "neutral", text: "Validando acceso..." });

    const supabase = createBrowserSupabaseClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      setBusy(null);
      setMessage({ tone: "error", text: error.message });
      return;
    }

    setMessage({ tone: "success", text: "Sesión iniciada." });
    router.refresh();
  }

  async function handleSignup(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const displayName = String(form.get("displayName") || "").trim();
    const email = String(form.get("email") || "").trim();
    const password = String(form.get("password") || "");

    if (displayName.length < 3 || displayName.length > 20) {
      setMessage({ tone: "error", text: "Display name must be 3-20 characters." });
      return;
    }

    setBusy("signup");
    setMessage({ tone: "neutral", text: "Enviando solicitud..." });

    const supabase = createBrowserSupabaseClient();
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { display_name: displayName }
      }
    });

    if (error) {
      setBusy(null);
      setMessage({ tone: "error", text: error.message });
      return;
    }

    setMessage({
      tone: "success",
      text: "Solicitud enviada. Tu acceso queda pendiente de aprobación manual."
    });
    setBusy(null);
    router.refresh();
  }

  return (
    <div className="auth-grid">
      <section className="auth-copy">
        <div className="eyebrow">Private beta</div>
        <h1>Analog Archive</h1>
        <p className="lead">
          Sign in with an approved account, or request beta access and wait for manual approval.
        </p>
      </section>

      <section className="auth-panels" aria-label="Access controls">
        <form className="auth-card" onSubmit={handleLogin}>
          <div className="status-label">Iniciar sesión</div>
          <label>
            Correo
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            Password
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          <Link className="inline-link" href="/forgot-password">
            Olvidé mi contraseña
          </Link>
          <button className="primary-action" type="submit" disabled={busy !== null}>
            {busy === "login" ? "Entrando..." : "Iniciar sesión"}
          </button>
        </form>

        <form className="auth-card" onSubmit={handleSignup}>
          <div className="status-label">Solicitar acceso</div>
          <label>
            Display name
            <input name="displayName" type="text" minLength={3} maxLength={20} required />
          </label>
          <label>
            Correo
            <input name="email" type="email" autoComplete="email" required />
          </label>
          <label>
            Password
            <input name="password" type="password" autoComplete="new-password" required />
          </label>
          <button className="secondary-action" type="submit" disabled={busy !== null}>
            {busy === "signup" ? "Enviando..." : "Solicitar acceso"}
          </button>
        </form>

        {message.text ? (
          <p className={`auth-message auth-message-${message.tone}`}>{message.text}</p>
        ) : null}
      </section>
    </div>
  );
}
