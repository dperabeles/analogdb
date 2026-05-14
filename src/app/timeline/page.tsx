import Link from "next/link";
import { getAnalyticsOverview } from "@/features/analytics/queries";
import { TimelinePanel } from "@/features/analytics/timeline-panel";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { AppShell } from "@/features/navigation/app-shell";

export const dynamic = "force-dynamic";

export default async function TimelinePage() {
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

  const overview = await getAnalyticsOverview();

  return (
    <AppShell active="timeline" profile={profile}>
      <div className="ed-page-header">
        <div className="ed-page-header-kicker">PÁG·03 &nbsp;·&nbsp; CRONOLOGÍA</div>
        <h1 className="ed-page-header-title">Tu film, <em>en el tiempo</em></h1>
        <div className="ed-page-header-sub">Historia cronológica del archivo, agrupada por mes</div>
      </div>
      <TimelinePanel overview={overview} />
    </AppShell>
  );
}
