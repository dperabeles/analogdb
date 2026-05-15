import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";
import { AppShell } from "@/features/navigation/app-shell";

export const dynamic = "force-dynamic";

export default async function AccountPage() {
  const { state, profile } = await getCurrentAccessProfile();

  if (state === "public") {
    return (
      <main className="gate-shell">
        <AccessGate />
      </main>
    );
  }

  if (state !== "approved") {
    return (
      <main className="app-shell">
        <header className="topbar">
          <div className="brand">
            <span className="brand-name">Analog Archive</span>
            <span className="brand-stage">Access</span>
          </div>
          <Link className="nav-link" href="/">
            Home
          </Link>
        </header>
        <section className="workspace">
          <AccessStatus state={state} profile={profile} />
        </section>
      </main>
    );
  }

  return (
    <AppShell active="account" profile={profile}>
      <div className="ed-page-header">
        <div>
          <div className="ed-page-header-kicker">CUENTA &nbsp;·&nbsp; ARCHIVO</div>
          <h1 className="ed-page-header-title">
            Identidad y <em>equipo</em>
          </h1>
          <div className="ed-page-header-sub">Accesos rápidos de cuenta para la experiencia móvil</div>
        </div>
      </div>

      <section className="dashboard-section">
        <div className="ed-section-head">
          <div className="ed-section-num">I.</div>
          <div>
            <h2 className="ed-section-title">Tu sesión</h2>
            <div className="ed-section-sub">{profile?.email || "Cuenta aprobada"}</div>
          </div>
        </div>
        <div className="account-action-grid">
          <Link className="account-action-card" href="/equipment">
            <span>II.</span>
            <strong>Cámaras y lentes</strong>
            <small>Gestiona equipo privado del usuario</small>
          </Link>
          {profile?.role === "admin" ? (
            <Link className="account-action-card" href="/admin">
              <span>III.</span>
              <strong>Panel admin</strong>
              <small>Aprobar usuarios y votar cambios</small>
            </Link>
          ) : null}
        </div>
        <div className="account-signout-row">
          <SignOutButton />
        </div>
      </section>
    </AppShell>
  );
}
