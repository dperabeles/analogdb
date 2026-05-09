import Link from "next/link";

export default function DashboardPage() {
  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Dashboard shell</span>
        </div>
        <Link className="nav-link" href="/">
          Home
        </Link>
      </header>

      <section className="workspace">
        <div className="hero">
          <div className="eyebrow">Migration shell</div>
          <h1>Dashboard</h1>
          <p className="lead">
            This route confirms the App Router baseline before moving auth, rolls, equipment, and admin flows.
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
