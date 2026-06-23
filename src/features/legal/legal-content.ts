import { promises as fs } from "node:fs";
import path from "node:path";

export type LegalSlug = "privacy" | "terms" | "cookies";

export interface LegalDoc {
  slug: LegalSlug;
  /** Título limpio (sin el sufijo "— Analog Archive"). */
  title: string;
  /** Fecha de "Última actualización" extraída del encabezado, o null. */
  updated: string | null;
  /** Cuerpo del documento (markdown) listo para renderizar. */
  body: string;
}

const FILE: Record<LegalSlug, string> = {
  privacy: "privacy.md",
  terms: "terms.md",
  cookies: "cookies.md",
};

/// Reescribe los links internos entre documentos (`./privacy-policy.md`) a las
/// rutas reales de Next (`/privacy`, `/terms`, `/cookies`). Los `.md` fuente
/// usan rutas relativas de archivo; en el sitio son rutas de navegación.
function rewriteInternalLinks(md: string): string {
  return md
    .replaceAll("./privacy-policy.md", "/privacy")
    .replaceAll("./terms-of-service.md", "/terms")
    .replaceAll("./cookie-policy.md", "/cookies")
    .replaceAll("privacy-policy.md", "/privacy")
    .replaceAll("terms-of-service.md", "/terms")
    .replaceAll("cookie-policy.md", "/cookies");
}

/// Lee y parsea uno de los documentos legales desde `src/content/legal/`.
///
/// Las páginas que lo consumen no usan APIs dinámicas, así que se prerenderizan
/// estáticamente: el `fs.readFile` ocurre en build, donde el archivo siempre
/// existe (incluido en Vercel vía `outputFileTracingIncludes`).
export async function loadLegalDoc(slug: LegalSlug): Promise<LegalDoc> {
  const file = path.join(process.cwd(), "src", "content", "legal", FILE[slug]);
  const raw = await fs.readFile(file, "utf8");
  const normalized = raw.replace(/\r\n/g, "\n");
  const lines = normalized.split("\n");

  // Título = primer H1, sin el sufijo " — Analog Archive".
  let title = "Analog Archive";
  const h1 = lines.find((l) => l.startsWith("# "));
  if (h1) {
    title = h1
      .replace(/^#\s+/, "")
      .replace(/\s+—\s+Analog Archive\s*$/, "")
      .trim();
  }

  const updMatch = normalized.match(/\*\*Última actualización:\*\*\s*(.+)/);
  const updated = updMatch ? updMatch[1].trim() : null;

  // El cuerpo empieza tras el primer separador `---` (cierra el encabezado de
  // título + metadatos). Si no hay separador, se usa todo el documento.
  const hrIdx = lines.findIndex((l) => l.trim() === "---");
  const bodyLines = hrIdx >= 0 ? lines.slice(hrIdx + 1) : lines;
  const body = rewriteInternalLinks(bodyLines.join("\n").trim());

  return { slug, title, updated, body };
}
