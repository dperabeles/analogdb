import Link from "next/link";
import { getAnalyticsOverview } from "@/features/analytics/queries";
import { StatsPanel } from "@/features/analytics/stats-panel";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";
import { MobileBottomNav } from "@/features/navigation/mobile-bottom-nav";

export const dynamic = "force-dynamic";

export default async function StatsPage() {
  const { state, profile } = await getCurrentAccessProfile();

  if (state === "public") {
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
          <AccessGate />
        </section>
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

  const overview = await getAnalyticsOverview();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Stats</span>
        </div>
        <div className="actions">
          <Link className="nav-link" href="/dashboard">
            Dashboard
          </Link>
          <Link className="nav-link" href="/timeline">
            Timeline
          </Link>
          <SignOutButton />
        </div>
      </header>
      <MobileBottomNav active="stats" />
      <section className="workspace">
        <div className="hero compact-hero">
          <div className="eyebrow">Analisis</div>
          <h1>Tu film, en cifras</h1>
          <p className="lead">Metricas y tendencias del archivo fotografico.</p>
        </div>
        <StatsPanel overview={overview} />
      </section>
    </main>
  );
}
