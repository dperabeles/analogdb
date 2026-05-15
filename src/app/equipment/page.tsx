import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { EquipmentPanel } from "@/features/equipment/equipment-panel";
import { getEquipmentOverview } from "@/features/equipment/queries";
import { AppShell } from "@/features/navigation/app-shell";

export const dynamic = "force-dynamic";

export default async function EquipmentPage() {
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

  const overview = await getEquipmentOverview();

  return (
    <AppShell active="equipment" profile={profile}>
      <div className="ed-page-header equipment-page-header">
        <div>
          <div className="ed-page-header-kicker">PÁG·04 &nbsp;·&nbsp; EQUIPO</div>
          <h1 className="ed-page-header-title">Tus cámaras, <em>en cifras</em></h1>
          <div className="ed-page-header-sub">
            {overview.cameras.length} {overview.cameras.length === 1 ? "cámara" : "cámaras"} en el catálogo
          </div>
        </div>
        <Link className="primary-action dashboard-masthead-action" href="#camera-form">
          + Agregar cámara
        </Link>
      </div>
      <EquipmentPanel overview={overview} />
    </AppShell>
  );
}
