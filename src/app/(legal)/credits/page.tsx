import type { Metadata } from "next";

import { LegalArticle } from "@/features/legal/legal-article";

export const metadata: Metadata = {
  title: "Créditos — Analog Archive",
  description:
    "Las fuentes del catálogo de cámaras de Analog Archive y sus licencias.",
};

export default function CreditsPage() {
  return <LegalArticle slug="credits" />;
}
