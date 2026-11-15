/// Languages the access pages speak. Spanish is the default, as in the app.
export type AccessLang = "es" | "en";

const SUPPORTED: readonly AccessLang[] = ["es", "en"];

function supported(value: string | undefined | null): AccessLang | null {
  const code = value?.trim().toLowerCase().split("-")[0];
  return SUPPORTED.find((l) => l === code) ?? null;
}

/// The browser's preferred supported language from Accept-Language, by q.
export function fromAcceptLanguage(header: string | null | undefined): AccessLang | null {
  if (!header) return null;
  const ranked = header
    .split(",")
    .map((part, index) => {
      const [tag, ...params] = part.trim().split(";");
      const q = params.map((p) => p.trim()).find((p) => p.startsWith("q="));
      const weight = q ? Number(q.slice(2)) : 1;
      return { tag, weight: Number.isFinite(weight) ? weight : 0, index };
    })
    .filter((entry) => entry.weight > 0)
    .sort((a, b) => b.weight - a.weight || a.index - b.index);
  for (const entry of ranked) {
    const lang = supported(entry.tag);
    if (lang) return lang;
  }
  return null;
}

/// The page language: `?lang=` from the email link (the account's language),
/// else the browser's, else Spanish.
export function resolveAccessLang(
  param: string | string[] | undefined,
  acceptLanguage: string | null | undefined,
): AccessLang {
  const fromLink = supported(Array.isArray(param) ? param[0] : param);
  return fromLink ?? fromAcceptLanguage(acceptLanguage) ?? "es";
}

/// Keeps the language on links between access pages.
export function withLang(href: string, lang: AccessLang): string {
  if (lang === "es") return href;
  return `${href}${href.includes("?") ? "&" : "?"}lang=${lang}`;
}
