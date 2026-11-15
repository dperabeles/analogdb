import type { Metadata } from "next";
import { AccessShell } from "@/features/auth/contacto-access";
import { PasswordRecoveryForm } from "@/features/auth/password-recovery-form";

export const metadata: Metadata = {
  title: "Recuperar acceso · Analog Archive",
};

export default function ForgotPasswordPage() {
  return (
    <AccessShell>
      <PasswordRecoveryForm />
    </AccessShell>
  );
}
