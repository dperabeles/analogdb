import Link from "next/link";

import { LegalFooter } from "@/features/legal/legal-footer";

/// Layout compartido para /privacy, /terms, /cookies y /contact (ANA-29):
/// header simple + tipografía editorial coherente con el site + footer global.
/// Contenido en español → `lang="es"` para accesibilidad (root es `lang="en"`).
export default function LegalLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <div className="legal-shell" lang="es">
      <header className="legal-topbar">
        <Link href="/" className="legal-brand">
          <span className="legal-brand-name">Analog Archive</span>
          <span className="legal-brand-stage">Legal</span>
        </Link>
        <Link href="/" className="legal-back">
          Volver al inicio
        </Link>
      </header>
      <main className="legal-main">{children}</main>
      <LegalFooter />
    </div>
  );
}
