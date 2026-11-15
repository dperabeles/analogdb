import type { Metadata } from "next";
import { ACCESS_COPY } from "@/features/auth/access-copy";
import { type AccessPageProps, accessLangFor } from "@/features/auth/access-lang-server";
import { AccessShell } from "@/features/auth/contacto-access";
import { UpdatePasswordForm } from "@/features/auth/update-password-form";

export async function generateMetadata(props: AccessPageProps): Promise<Metadata> {
  const lang = await accessLangFor(props);
  return { title: `${ACCESS_COPY[lang].reset.meta} · Analog Archive` };
}

export default async function Page(props: AccessPageProps) {
  const lang = await accessLangFor(props);
  return (
    <AccessShell lang={lang}>
      <UpdatePasswordForm lang={lang} />
    </AccessShell>
  );
}
