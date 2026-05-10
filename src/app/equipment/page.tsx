import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";
import { EquipmentPanel } from "@/features/equipment/equipment-panel";
import { getEquipmentOverview } from "@/features/equipment/queries";

export const dynamic = "force-dynamic";

export default async function EquipmentPage() {
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

  const overview = await getEquipmentOverview();

  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Equipment</span>
        </div>
        <div className="actions">
          <Link className="nav-link" href="/dashboard">
            Dashboard
          </Link>
          <SignOutButton />
        </div>
      </header>
      <section className="workspace">
        <div className="hero compact-hero">
          <div className="eyebrow">Catalogo privado</div>
          <h1>Equipo</h1>
          <p className="lead">Administra camaras y lentes sin contaminar el catalogo de otros beta testers.</p>
        </div>
        <EquipmentPanel overview={overview} />
      </section>
    </main>
  );
}
