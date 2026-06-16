import Link from "next/link";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { Components } from "react-markdown";

import { loadLegalDoc, type LegalSlug } from "./legal-content";

// Links internos (`/privacy`, `/terms`, `/cookies`, `/contact`) usan next/link
// para navegación SPA; los externos abren en pestaña nueva con rel seguro.
const components: Components = {
  a({ href, children }) {
    if (href && href.startsWith("/")) {
      return <Link href={href}>{children}</Link>;
    }
    const external = !!href && /^https?:/i.test(href);
    return external ? (
      <a href={href} target="_blank" rel="noopener noreferrer">
        {children}
      </a>
    ) : (
      <a href={href}>{children}</a>
    );
  },
};

export async function LegalArticle({ slug }: { slug: LegalSlug }) {
  const doc = await loadLegalDoc(slug);

  return (
    <article className="legal-article">
      <header className="legal-head">
        <span className="legal-kicker">Analog Archive · Legal</span>
        <h1 className="legal-title">{doc.title}</h1>
        {doc.updated && (
          <p className="legal-updated">Última actualización · {doc.updated}</p>
        )}
      </header>
      <div className="legal-prose">
        <Markdown remarkPlugins={[remarkGfm]} components={components}>
          {doc.body}
        </Markdown>
      </div>
    </article>
  );
}
