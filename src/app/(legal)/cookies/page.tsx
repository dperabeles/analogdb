import type { Metadata } from "next";

import { LegalArticle } from "@/features/legal/legal-article";

export const metadata: Metadata = {
  title: "Política de Cookies — Analog Archive",
  description:
    "Qué cookies y tecnologías similares usa Analog Archive. Sin publicidad ni rastreo de terceros.",
};

export default function CookiesPage() {
  return <LegalArticle slug="cookies" />;
}
