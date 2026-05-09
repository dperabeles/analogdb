import Link from "next/link";
import { UpdatePasswordForm } from "@/features/auth/update-password-form";

export default function ResetPasswordPage() {
  return (
    <main className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-name">Analog Archive</span>
          <span className="brand-stage">New password</span>
        </div>
        <Link className="nav-link" href="/dashboard">
          Login
        </Link>
      </header>
      <section className="workspace auth-workspace">
        <UpdatePasswordForm />
      </section>
    </main>
  );
}
