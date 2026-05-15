import Link from "next/link";
import { PasswordRecoveryForm } from "@/features/auth/password-recovery-form";

export default function ForgotPasswordPage() {
  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">Recovery</span>
        </div>
        <Link className="nav-link" href="/dashboard">
          Volver
        </Link>
      </header>
      <section className="workspace auth-workspace">
        <PasswordRecoveryForm />
      </section>
    </main>
  );
}
