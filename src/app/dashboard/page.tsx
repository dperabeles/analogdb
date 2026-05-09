import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
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

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Dashboard shell</span>
        </div>
        <SignOutButton />
      </header>

      <section className="workspace">
        <div className="hero">
          <div className="eyebrow">Migration shell</div>
          <h1>Dashboard</h1>
          <p className="lead">
            {profile?.displayName || "Approved beta tester"}, this route confirms the auth gate before moving rolls,
            equipment, and admin flows.
          </p>
        </div>

        <div className="status-grid" aria-label="Migration status">
          <div className="status-cell">
            <div className="status-label">Phase</div>
            <div className="status-value">Shell</div>
            <div className="status-note">Next.js app structure and build pipeline.</div>
          </div>
          <div className="status-cell">
            <div className="status-label">Backend</div>
            <div className="status-value">Shared</div>
            <div className="status-note">Supabase remains the source of truth.</div>
          </div>
          <div className="status-cell">
            <div className="status-label">Beta</div>
            <div className="status-value">Stable</div>
            <div className="status-note">GitHub Pages remains the active beta line.</div>
          </div>
        </div>
      </section>
    </main>
  );
}
