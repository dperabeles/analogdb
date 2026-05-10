import Link from "next/link";
import { getAnalyticsOverview } from "@/features/analytics/queries";
import { TimelinePanel } from "@/features/analytics/timeline-panel";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";

export const dynamic = "force-dynamic";

export default async function TimelinePage() {
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
          <span className="brand-stage">Timeline</span>
        </div>
        <div className="actions">
          <Link className="nav-link" href="/dashboard">
            Dashboard
          </Link>
          <Link className="nav-link" href="/stats">
            Stats
          </Link>
          <SignOutButton />
        </div>
      </header>
      <section className="workspace">
        <div className="hero compact-hero">
          <div className="eyebrow">Cronologia</div>
          <h1>Tu film, en el tiempo</h1>
          <p className="lead">Historia cronologica del archivo, agrupada por mes.</p>
        </div>
        <TimelinePanel overview={overview} />
      </section>
    </main>
  );
}
