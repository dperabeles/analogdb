import Link from "next/link";

/// Footer global con los links legales requeridos (ANA-30): privacidad,
/// términos, cookies, contacto, email de soporte e Instagram.
export function LegalFooter() {
  const year = new Date().getFullYear();

  return (
    <footer className="legal-footer">
      <div className="legal-footer-inner">
        <div className="legal-footer-brand">
          <span className="legal-footer-name">Analog Archive</span>
          <span className="legal-footer-tag">
            Bitácora privada de fotografía analógica
          </span>
        </div>
        <nav className="legal-footer-nav" aria-label="Enlaces legales">
          <Link href="/privacy">Privacidad</Link>
          <Link href="/terms">Términos</Link>
          <Link href="/cookies">Cookies</Link>
          <Link href="/contact">Contacto</Link>
          <a href="mailto:hello@analog-archive.com">hello@analog-archive.com</a>
          <a
            href="https://instagram.com/analog.archive.app"
            target="_blank"
            rel="noopener noreferrer"
          >
            @analog.archive.app
          </a>
        </nav>
        <p className="legal-footer-copy">
          © {year} Analog Archive · Diego Perabeles · Monterrey, México
        </p>
      </div>
    </footer>
  );
}
