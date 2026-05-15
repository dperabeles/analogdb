import Link from "next/link";
import { AdminPanel } from "@/features/admin/admin-panel";
import { getAdminOverview } from "@/features/admin/queries";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { AppShell } from "@/features/navigation/app-shell";

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
      <AppShell active="admin" profile={profile}>
        <div className="ed-page-header">
          <div>
            <div className="ed-page-header-kicker">PÁG·06 &nbsp;·&nbsp; ADMIN</div>
            <h1 className="ed-page-header-title">Admin</h1>
            <div className="ed-page-header-sub">Permisos restringidos para fundador y administradores</div>
          </div>
        </div>
        <section className="auth-workspace">
          <div className="auth-status">
            <div className="eyebrow">Admin required</div>
            <h1>Sin acceso admin</h1>
            <p className="lead">Tu cuenta esta aprobada, pero no tiene permisos de administracion.</p>
          </div>
        </section>
      </AppShell>
    );
  }

  const overview = await getAdminOverview();

  return (
    <AppShell active="admin" profile={profile}>
      <div className="ed-page-header">
        <div>
          <div className="ed-page-header-kicker">PÁG·06 &nbsp;·&nbsp; ADMIN</div>
          <h1 className="ed-page-header-title">
            Founder <em>workflow</em>
          </h1>
          <div className="ed-page-header-sub">Aprobación de usuarios, reactivación y votación de roles</div>
        </div>
      </div>
      <AdminPanel overview={overview} />
    </AppShell>
  );
}
