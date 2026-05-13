import Link from "next/link";
import { notFound } from "next/navigation";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";
import { MobileBottomNav } from "@/features/navigation/mobile-bottom-nav";
import { getRollByCode } from "@/features/rolls/queries";
import { RollForm } from "@/features/rolls/roll-form";

type EditRollPageProps = {
  params: Promise<{
    code: string;
  }>;
};

export const dynamic = "force-dynamic";

export default async function EditRollPage({ params }: EditRollPageProps) {
  const { state, profile } = await getCurrentAccessProfile();
  const { code } = await params;
  const decodedCode = decodeURIComponent(code);

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

  const { roll, error } = await getRollByCode(decodedCode);
  if (!roll && !error) notFound();

  return (
    <main className="app-shell approved-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Edit roll</span>
        </div>
        <div className="actions">
          <Link className="nav-link" href={`/rolls/${encodeURIComponent(decodedCode)}`}>
            Detail
          </Link>
          <Link className="nav-link" href="/dashboard">
            Dashboard
          </Link>
          <Link className="nav-link" href="/stats">
            Stats
          </Link>
          <Link className="nav-link" href="/timeline">
            Timeline
          </Link>
          <Link className="nav-link" href="/equipment">
            Equipo
          </Link>
          <SignOutButton />
        </div>
      </header>
      <MobileBottomNav active="edit" />
      <section className="workspace">
        {error ? <p className="auth-message auth-message-error">No se pudo cargar el roll: {error}</p> : null}
        {roll ? <RollForm roll={roll} /> : null}
      </section>
    </main>
  );
}
