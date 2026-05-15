import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { AppShell } from "@/features/navigation/app-shell";
import { RollForm } from "@/features/rolls/roll-form";

export const dynamic = "force-dynamic";

export default async function NewRollPage() {
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

  return (
    <AppShell active="new" profile={profile}>
      <div className="ed-page-header">
        <div>
          <div className="ed-page-header-kicker">PÁG·02 &nbsp;·&nbsp; DATABASE</div>
          <h1 className="ed-page-header-title">
            Nuevo rollo, <em>al archivo</em>
          </h1>
          <div className="ed-page-header-sub">Captura film, cámara, workflow y notas del rollo</div>
        </div>
      </div>
      <RollForm />
    </AppShell>
  );
}
