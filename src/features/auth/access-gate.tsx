"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { type FormEvent, useEffect, useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

type Message = {
  tone: "neutral" | "error" | "success";
  text: string;
};

type LandingMetrics = {
  totalRolls: number;
  topStockLabel: string;
  topStockCount: number;
  supportedFormats: number;
  uniqueLocations: number;
};

const LANDING_METRICS_FALLBACK: LandingMetrics = {
  totalRolls: 0,
  topStockLabel: "—",
  topStockCount: 0,
  supportedFormats: 6,
  uniqueLocations: 0
};

export function AccessGate() {
  const router = useRouter();
  const [message, setMessage] = useState<Message>({
    tone: "neutral",
    text: ""
  });
  const [busy, setBusy] = useState<"login" | "signup" | null>(null);
  const [metrics, setMetrics] = useState<LandingMetrics>(LANDING_METRICS_FALLBACK);

  useEffect(() => {
    let ignore = false;

    async function loadLandingMetrics() {
      const supabase = createBrowserSupabaseClient() as unknown as {
        rpc: (fn: "landing_metrics") => Promise<{ data: unknown; error: { message: string } | null }>;
      };
      const { data, error } = await supabase.rpc("landing_metrics");
      if (ignore || error || !data) return;

      const payload = Array.isArray(data) ? data[0] : data;
      const record = payload && typeof payload === "object" && "landing_metrics" in payload
        ? (payload as { landing_metrics?: unknown }).landing_metrics
        : payload;

      if (!record || typeof record !== "object") return;
      const values = record as Partial<Record<keyof LandingMetrics, unknown>>;
      setMetrics({
        totalRolls: Number(values.totalRolls || 0),
        topStockLabel: String(values.topStockLabel || "—"),
        topStockCount: Number(values.topStockCount || 0),
        supportedFormats: Number(values.supportedFormats || 6),
        uniqueLocations: Number(values.uniqueLocations || 0)
      });
    }

    loadLandingMetrics().catch(() => undefined);
    return () => {
      ignore = true;
    };
  }, []);

  const metricPills = [
    {
      value: String(metrics.totalRolls),
      label: "Rollos registrados",
      sub: "entre todos los usuarios"
    },
    {
      value: metrics.topStockLabel,
      label: "Rollo más usado",
      sub: `${metrics.topStockCount} registros globales`
    },
    {
      value: String(metrics.supportedFormats),
      label: "Formatos soportados",
      sub: "35, 120, Super8, 110, 16mm y LF"
    },
    {
      value: String(metrics.uniqueLocations),
      label: "Lugares únicos",
      sub: "seleccionados en el archivo"
    }
  ];

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
    <div className="gate-frame">
      <section className="gate-copy">
        <div className="gate-kicker">Private beta</div>
        <h1>Track every roll from camera to archive.</h1>
        <p>
          A private archive for film photographers shooting analog. Register by email, wait for manual approval,
          and keep your rolls, stats, cameras and workflow isolated from everyone else.
        </p>

        <div className="gate-copy-footer">
          <div className="gate-marquee" aria-label="Public archive metrics">
            <div className="gate-marquee-track">
              {[...metricPills, ...metricPills].map((metric, index) => (
                <div className="gate-metric-pill" key={`${metric.label}-${index}`}>
                  <div className="gate-metric-value">{metric.value}</div>
                  <div className="gate-metric-copy">
                    <span className="gate-metric-label">{metric.label}</span>
                    <span className="gate-metric-sub">{metric.sub}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
          <p className="gate-founder">
            Un proyecto de:{" "}
            <a
              href="https://www.instagram.com/perabeles.jpg?igsh=MXg1dXczaDgwaWJobg%3D%3D&utm_source=qr"
              target="_blank"
              rel="noopener noreferrer"
            >
              Diego Perabeles
            </a>.
          </p>
        </div>
      </section>

      <section className="auth-panels gate-panels" aria-label="Access controls">
        <form className="auth-card" onSubmit={handleLogin}>
          <div className="status-label">Iniciar sesión</div>
          <label>
            Correo
            <input name="email" type="email" autoComplete="email" placeholder="Correo" required />
          </label>
          <label>
            Password
            <input name="password" type="password" autoComplete="current-password" placeholder="Password" required />
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
            <input name="displayName" type="text" minLength={3} maxLength={20} placeholder="Display name" required />
          </label>
          <label>
            Correo
            <input name="email" type="email" autoComplete="email" placeholder="Correo" required />
          </label>
          <label>
            Password
            <input name="password" type="password" autoComplete="new-password" placeholder="Password" required />
          </label>
          <p className="gate-help">El display name será visible dentro de tu archivo y no podrá cambiarse después.</p>
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
