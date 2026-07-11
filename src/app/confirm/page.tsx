import Link from "next/link";
import { ConfirmAccount } from "@/features/auth/confirm-account";

export default function ConfirmPage() {
  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Confirm account</span>
        </div>
        <Link className="nav-link" href="/dashboard">
          Login
        </Link>
      </header>
      <section className="workspace auth-workspace">
        <ConfirmAccount />
      </section>
    </main>
  );
}
