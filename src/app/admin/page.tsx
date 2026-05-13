import Link from "next/link";
import { AdminPanel } from "@/features/admin/admin-panel";
import { getAdminOverview } from "@/features/admin/queries";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";
import { MobileBottomNav } from "@/features/navigation/mobile-bottom-nav";

export const dynamic = "force-dynamic";

export default async function AdminPage() {
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

  if (profile?.role !== "admin") {
    return (
      <main className="app-shell">
        <header className="topbar">
          <div className="brand">
            <span className="brand-name">Analog Archive</span>
            <span className="brand-stage">Admin</span>
          </div>
          <div className="actions">
            <Link className="nav-link" href="/dashboard">
              Dashboard
            </Link>
            <Link className="nav-link" href="/rolls/new">
              Nuevo
            </Link>
            <Link className="nav-link" href="/stats">
              Stats
            </Link>
            <Link className="nav-link" href="/timeline">
              Timeline
            </Link>
            <Link className="nav-link" href="/equipment">
              Equipo
            </Link>
            <SignOutButton />
          </div>
        </header>
        <MobileBottomNav active="admin" />
        <section className="workspace auth-workspace">
          <div className="auth-status">
            <div className="eyebrow">Admin required</div>
            <h1>Sin acceso admin</h1>
            <p className="lead">Tu cuenta esta aprobada, pero no tiene permisos de administracion.</p>
          </div>
        </section>
      </main>
    );
  }

  const overview = await getAdminOverview();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Admin</span>
        </div>
        <div className="actions">
          <Link className="nav-link" href="/dashboard">
            Dashboard
          </Link>
          <Link className="nav-link" href="/rolls/new">
            Nuevo
          </Link>
          <Link className="nav-link" href="/stats">
            Stats
          </Link>
          <Link className="nav-link" href="/timeline">
            Timeline
          </Link>
          <Link className="nav-link" href="/equipment">
            Equipo
          </Link>
          <SignOutButton />
        </div>
      </header>
      <MobileBottomNav active="admin" />

      <section className="workspace">
        <div className="hero compact-hero">
          <div className="eyebrow">Founder workflow</div>
          <h1>Admin</h1>
          <p className="lead">Aprobacion de usuarios, reactivacion de rechazados y votacion de cambios de rol.</p>
        </div>
        <AdminPanel overview={overview} />
      </section>
    </main>
  );
}
