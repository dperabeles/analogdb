import Link from "next/link";
import type { ReactNode } from "react";
import type { AccessProfile } from "@/features/auth/profile";
import { SignOutButton } from "@/features/auth/sign-out-button";
import { MobileBottomNav } from "@/features/navigation/mobile-bottom-nav";

type AppShellProps = {
  active: "dashboard" | "new" | "stats" | "timeline" | "equipment" | "admin" | "detail" | "edit";
  profile: AccessProfile | null;
  children: ReactNode;
};

const NAV_ITEMS = [
  { key: "dashboard", href: "/dashboard", label: "Dashboard", num: "01" },
  { key: "new", href: "/rolls/new", label: "Database", num: "02" },
  { key: "timeline", href: "/timeline", label: "Timeline", num: "03" },
  { key: "equipment", href: "/equipment", label: "Cámaras", num: "04" },
  { key: "stats", href: "/stats", label: "Estadísticas", num: "05" }
] as const;

function avatarInitial(profile: AccessProfile | null) {
  const value = profile?.displayName || profile?.email || "A";
  return value.trim().charAt(0).toUpperCase() || "A";
}

export function AppShell({ active, profile, children }: AppShellProps) {
  const displayName = profile?.displayName || "Archivo personal";
  const dateLabel = new Date().toLocaleDateString("es-MX", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric"
  });

  return (
    <main className="app-shell approved-shell">
      <aside className="topbar ed-sidebar" aria-label="Navegación principal">
        <div className="brand ed-brand">
          <div className="brand-icon" aria-hidden="true">
            <svg viewBox="0 0 110 135" xmlns="http://www.w3.org/2000/svg">
              <path d="M95.3,10.6H14.7c-7.1,0-12.9,5.8-12.9,12.9v85.9c0,7.1,5.8,12.9,12.9,12.9h80.6c7.1,0,12.9-5.8,12.9-12.9V23.5C108.2,16.4,102.4,10.6,95.3,10.6z M23.3,113.7h-8.6c-2.4,0-4.3-1.9-4.3-4.3V103h12.9L23.3,113.7z M23.3,94.4H10.4V81.5h12.9V94.4z M23.3,72.9H10.4V60h12.9V72.9z M23.3,51.4H10.4V38.5h12.9V51.4z M23.3,29.9H10.4v-6.4c0-2.4,1.9-4.3,4.3-4.3h8.6L23.3,29.9z M99.6,109.4c0,2.4-1.9,4.3-4.3,4.3h-8.6V103h12.9L99.6,109.4z M99.6,94.4H86.7V81.5h12.9V94.4z M99.6,72.9H86.7V60h12.9V72.9z M99.6,51.4H86.7V38.5h12.9V51.4z M99.6,29.9H86.7V19.2h8.6c2.4,0,4.3,1.9,4.3,4.3L99.6,29.9z" />
            </svg>
          </div>
          <div className="ed-brand-copy">
            <span className="brand-tag">Analog</span>
            <span className="brand-name">Archive</span>
          </div>
        </div>

        <nav className="actions nav-section" aria-label="Archivo">
          {NAV_ITEMS.map((item) => (
            <Link
              aria-current={active === item.key ? "page" : undefined}
              className={`nav-link nav-item${active === item.key ? " active" : ""}`}
              href={item.href}
              key={item.key}
            >
              <span className="ed-nav-num">{item.num}</span>
              {item.label}
            </Link>
          ))}
          {profile?.role === "admin" ? (
            <Link
              aria-current={active === "admin" ? "page" : undefined}
              className={`nav-link nav-item${active === "admin" ? " active" : ""}`}
              href="/admin"
            >
              <span className="ed-nav-num">06</span>
              Admin
            </Link>
          ) : null}
        </nav>

        <div className="sidebar-primary-action">
          <Link className="primary-action" href="/rolls/new">
            + Cargar rollo
          </Link>
        </div>

        <div className="sidebar-account-card">
          <div className="sidebar-account-main">
            <div className="sidebar-avatar">{avatarInitial(profile)}</div>
            <div className="sidebar-account-copy">
              <strong>{displayName}</strong>
              <span>Archivo personal</span>
            </div>
          </div>
          <SignOutButton />
        </div>
      </aside>

      <div className="desktop-archive-bar" aria-label="Ubicación actual">
        <span>ARCHIVE</span>
        <span>/</span>
        <span>{active === "dashboard" ? "DASHBOARD" : active.toUpperCase()}</span>
        <span>/</span>
        <span>{dateLabel}</span>
      </div>

      <MobileBottomNav active={active} />

      <section className="workspace ed-page-inner">{children}</section>
    </main>
  );
}
