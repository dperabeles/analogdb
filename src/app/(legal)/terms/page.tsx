import type { Metadata } from "next";

import { LegalArticle } from "@/features/legal/legal-article";

export const metadata: Metadata = {
  title: "Términos de Servicio — Analog Archive",
  description:
    "Las reglas para usar Analog Archive: licencia de uso, contenido del usuario, responsabilidades y limitaciones.",
};

export default function TermsPage() {
  return <LegalArticle slug="terms" />;
}
