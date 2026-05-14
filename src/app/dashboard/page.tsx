import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { AppShell } from "@/features/navigation/app-shell";
import { DashboardOverview } from "@/features/rolls/dashboard-overview";
import { getRolls } from "@/features/rolls/queries";

type DashboardPageProps = {
  searchParams?: Promise<{
    status?: string;
    q?: string;
    sort?: string;
  }>;
};

export const dynamic = "force-dynamic";

export default async function DashboardPage({ searchParams }: DashboardPageProps) {
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

  await searchParams;
  const { rolls, error } = await getRolls();
  const activeRolls = rolls.filter((roll) => roll.status !== "Developed" && roll.status !== "Archived").length;
  const stockCount = new Set(rolls.map((roll) => roll.filmStock).filter(Boolean)).size;

  return (
    <AppShell active="dashboard" profile={profile}>
      <div className="dashboard-masthead">
        <div className="dashboard-masthead-main">
          <div>
            <h1>
              Cuaderno de <em>laboratorio</em>
            </h1>
            <p className="dashboard-masthead-summary">
              <em>{activeRolls}</em> rollos en proceso activo. <em>{rolls.length}</em> en archivo histórico.
            </p>
          </div>
          <Link className="primary-action dashboard-masthead-action" href="/rolls/new">
            + Cargar rollo nuevo
          </Link>
        </div>
        <div className="dashboard-summary-grid" aria-label="Archive summary">
          <div>
            <span>Total rolls</span>
            <strong>{rolls.length}</strong>
          </div>
          <div>
            <span>Activos</span>
            <strong>{activeRolls}</strong>
          </div>
          <div>
            <span>Stocks</span>
            <strong>{stockCount}</strong>
          </div>
          <div>
            <span>Source</span>
            <strong>Supabase</strong>
          </div>
        </div>
      </div>

      {error ? <p className="auth-message auth-message-error">No se pudieron cargar los rolls: {error}</p> : null}
      <DashboardOverview rolls={rolls} />
    </AppShell>
  );
}
