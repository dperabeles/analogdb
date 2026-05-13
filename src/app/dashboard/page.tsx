import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";
import { MobileBottomNav } from "@/features/navigation/mobile-bottom-nav";
import { getRolls } from "@/features/rolls/queries";
import { RollList } from "@/features/rolls/roll-list";
import { normalizeRollSort, type RollFilters } from "@/features/rolls/roll-types";

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

  const params = searchParams ? await searchParams : {};
  const filters: RollFilters = {
    status: params.status,
    q: params.q,
    sort: normalizeRollSort(params.sort)
  };
  const { rolls, error } = await getRolls();
  const activeRolls = rolls.filter((roll) => roll.status !== "Developed" && roll.status !== "Archived").length;
  const stockCount = new Set(rolls.map((roll) => roll.filmStock).filter(Boolean)).size;

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Dashboard</span>
        </div>
        <div className="actions">
          {profile?.role === "admin" ? (
            <Link className="nav-link" href="/admin">
              Admin
            </Link>
          ) : null}
          <Link className="nav-link" href="/stats">
            Stats
          </Link>
          <Link className="nav-link" href="/timeline">
            Timeline
          </Link>
          <Link className="nav-link" href="/equipment">
            Equipo
          </Link>
          <Link className="primary-action" href="/rolls/new">
            Agregar rollo
          </Link>
          <SignOutButton />
        </div>
      </header>
      <MobileBottomNav active="dashboard" />

      <section className="workspace">
        <div className="dashboard-masthead">
          <div className="dashboard-masthead-meta">
            <span>Private archive</span>
            <span>{profile?.displayName || "Approved beta tester"}</span>
          </div>
          <div className="dashboard-masthead-main">
            <div>
              <div className="eyebrow">Migration preview</div>
              <h1>Archive Index</h1>
            </div>
            <Link className="primary-action dashboard-masthead-action" href="/rolls/new">
              Agregar rollo
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

        <RollList rolls={rolls} filters={filters} error={error} />
      </section>
    </main>
  );
}
