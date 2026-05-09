import Link from "next/link";

export default function HomePage() {
  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Next.js migration</span>
        </div>
        <Link className="nav-link" href="/dashboard">
          Dashboard
        </Link>
      </header>

      <section className="workspace">
        <div className="hero">
          <div className="eyebrow">Private beta</div>
          <h1>Analog Archive</h1>
          <p className="lead">
            A focused workspace for the Next.js migration of the existing analog photography archive.
          </p>
          <div className="actions">
            <Link className="primary-action" href="/dashboard">
              Open dashboard
            </Link>
            <a className="secondary-action" href="/analog-db-dashboard.html">
              Legacy dashboard
            </a>
          </div>
        </div>
      </section>
    </main>
  );
}
