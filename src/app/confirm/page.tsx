import type { Metadata } from "next";
import { ConfirmAccount } from "@/features/auth/confirm-account";
import { AccessShell } from "@/features/auth/contacto-access";

export const metadata: Metadata = {
  title: "Confirmar cuenta · Analog Archive",
};

export default function ConfirmPage() {
  return (
    <AccessShell>
      <ConfirmAccount />
    </AccessShell>
  );
}
