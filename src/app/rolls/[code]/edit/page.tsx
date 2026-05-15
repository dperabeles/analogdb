import Link from "next/link";
import { notFound } from "next/navigation";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { AppShell } from "@/features/navigation/app-shell";
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

  const { roll, error } = await getRollByCode(decodedCode);
  if (!roll && !error) notFound();

  return (
    <AppShell active="edit" profile={profile}>
      <div className="ed-page-header">
        <div>
          <div className="ed-page-header-kicker">EDITAR &nbsp;·&nbsp; ROLLO</div>
          <h1 className="ed-page-header-title">{decodedCode}</h1>
          <div className="ed-page-header-sub">Actualiza la ficha del rollo sin cambiar el archivo base</div>
        </div>
      </div>
      <div className="roll-editor-backlink">
        <Link className="ed-modal-edit-btn" href={`/rolls/${encodeURIComponent(decodedCode)}`}>
          Volver al detalle
        </Link>
      </div>
      {error ? <p className="auth-message auth-message-error">No se pudo cargar el roll: {error}</p> : null}
      {roll ? <RollForm roll={roll} /> : null}
    </AppShell>
  );
}
