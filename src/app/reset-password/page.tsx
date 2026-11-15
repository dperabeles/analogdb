import type { Metadata } from "next";
import { AccessShell } from "@/features/auth/contacto-access";
import { UpdatePasswordForm } from "@/features/auth/update-password-form";

export const metadata: Metadata = {
  title: "Nueva contraseña · Analog Archive",
};

export default function ResetPasswordPage() {
  return (
    <AccessShell>
      <UpdatePasswordForm />
    </AccessShell>
  );
}
