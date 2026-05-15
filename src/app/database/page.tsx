import Link from "next/link";
import { AccessGate } from "@/features/auth/access-gate";
import { AccessStatus } from "@/features/auth/access-status";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { AppShell } from "@/features/navigation/app-shell";
import { getRolls } from "@/features/rolls/queries";
import { RollList } from "@/features/rolls/roll-list";
import { normalizeRollSort } from "@/features/rolls/roll-types";

type DatabasePageProps = {
  searchParams?: Promise<{
    status?: string;
    q?: string;
    filmType?: string;
    format?: string;
    expFresh?: string;
    camera?: string;
    lab?: string;
    sort?: string;
  }>;
};

export const dynamic = "force-dynamic";

export default async function DatabasePage({ searchParams }: DatabasePageProps) {
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

  const params = await searchParams;
  const filters = {
    status: params?.status,
    q: params?.q,
    filmType: params?.filmType,
    format: params?.format,
    expFresh: params?.expFresh,
    camera: params?.camera,
    lab: params?.lab,
    sort: normalizeRollSort(params?.sort)
  };
  const { rolls, error } = await getRolls();

  return (
    <AppShell active="database" profile={profile}>
      <div className="ed-page-header">
        <div>
          <div className="ed-page-header-kicker">PÁG·02 &nbsp;·&nbsp; BASE DE DATOS</div>
          <h1 className="ed-page-header-title">
            Tu archivo, <em>en datos</em>
          </h1>
          <div className="ed-page-header-sub">Registro completo de todos los rollos del archivo</div>
        </div>
        <Link className="primary-action dashboard-masthead-action" href="/rolls/new">
          + Agregar rollo
        </Link>
      </div>

      <RollList rolls={rolls} filters={filters} error={error} />
    </AppShell>
  );
}
