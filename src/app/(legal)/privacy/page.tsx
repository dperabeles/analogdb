import type { Metadata } from "next";

import { LegalArticle } from "@/features/legal/legal-article";

export const metadata: Metadata = {
  title: "Aviso de Privacidad — Analog Archive",
  description:
    "Cómo Analog Archive recopila, usa y protege tus datos personales, y los derechos que tienes sobre ellos.",
};

export default function PrivacyPage() {
  return <LegalArticle slug="privacy" />;
}
