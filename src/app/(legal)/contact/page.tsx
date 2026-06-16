import type { Metadata } from "next";

import { ContactForm } from "@/features/legal/contact-form";

export const metadata: Metadata = {
  title: "Contacto — Analog Archive",
  description:
    "Escríbenos sobre privacidad, exportar o eliminar tus datos, o cualquier asunto legal.",
};

export default function ContactPage() {
  return (
    <article className="legal-article">
      <header className="legal-head">
        <span className="legal-kicker">Analog Archive · Legal</span>
        <h1 className="legal-title">Contacto</h1>
        <p className="legal-updated">
          Privacidad, tus datos, o cualquier asunto legal
        </p>
      </header>

      <div className="legal-prose">
        <p>
          ¿Tienes preguntas sobre tus datos, quieres exportarlos o eliminar tu
          cuenta? Usa el formulario y te responderemos, o escríbenos
          directamente:
        </p>
        <ul>
          <li>
            <strong>Privacidad / legal:</strong>{" "}
            <a href="mailto:legal@analog-archive.com">
              legal@analog-archive.com
            </a>
          </li>
          <li>
            <strong>Soporte general:</strong>{" "}
            <a href="mailto:hello@analog-archive.com">
              hello@analog-archive.com
            </a>
          </li>
        </ul>
      </div>

      <ContactForm />
    </article>
  );
}
