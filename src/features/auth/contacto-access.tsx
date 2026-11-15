import type { ReactNode } from "react";
import { Instrument_Sans } from "next/font/google";
import styles from "./contacto-access.module.css";

/// Contacto's only typeface (weights 400–600 are the ones used here).
const instrument = Instrument_Sans({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-instrument",
  display: "swap",
});

/// The film-strip mark, the same SVG as the app's header.
function Mark() {
  return (
    <svg width="28" height="33" viewBox="1.8 10.6 106.4 111.7" fill="#d94a2a" aria-hidden="true">
      <path d="M95.3,10.6H14.7c-7.1,0-12.9,5.8-12.9,12.9v85.9c0,7.1,5.8,12.9,12.9,12.9h80.6c7.1,0,12.9-5.8,12.9-12.9V23.5C108.2,16.4,102.4,10.6,95.3,10.6z M23.3,113.7h-8.6c-2.4,0-4.3-1.9-4.3-4.3V103h12.9L23.3,113.7z M23.3,94.4H10.4V81.5h12.9V94.4z M23.3,72.9H10.4V60h12.9V72.9z M23.3,51.4H10.4V38.5h12.9V51.4z M23.3,29.9H10.4v-6.4c0-2.4,1.9-4.3,4.3-4.3h8.6L23.3,29.9z M99.6,109.4c0,2.4-1.9,4.3-4.3,4.3h-8.6V103h12.9L99.6,109.4z M99.6,94.4H86.7V81.5h12.9V94.4z M99.6,72.9H86.7V60h12.9V72.9z M99.6,51.4H86.7V38.5h12.9V51.4z M99.6,29.9H86.7V19.2h8.6c2.4,0,4.3,1.9,4.3,4.3L99.6,29.9z" />
    </svg>
  );
}

/// Page shell: dot field, compact brand, the state, and the site link.
export function AccessShell({ children, lang = "es" }: { children: ReactNode; lang?: string }) {
  return (
    <div className={`${styles.shell} ${instrument.variable}`} lang={lang}>
      <div className={styles.dots} aria-hidden="true" />
      <main className={styles.page}>
        <a className={styles.brand} href="https://analog-archive.com" aria-label="analog archive">
          <span className={styles.mark}>
            <Mark />
          </span>
          <span className={styles.word}>
            analog
            <br />
            archive
          </span>
        </a>
        {children}
        <div className={styles.foot}>
          <a href="https://analog-archive.com">analog-archive.com &#8599;</a>
        </div>
      </main>
    </div>
  );
}

type Action = { label: string; href: string };

/// One access state: eyebrow, two-line title, optional copy, the numbered
/// plate, an optional progress line and up to two actions.
export function AccessState({
  eyebrow,
  title,
  copy,
  plateTitle,
  plateNote,
  progress = false,
  primary,
  secondary,
  live = false,
}: {
  eyebrow: string;
  title: string;
  copy?: string;
  plateTitle?: string;
  plateNote?: ReactNode;
  progress?: boolean;
  primary?: Action;
  secondary?: Action;
  live?: boolean;
}) {
  return (
    <section className={styles.state} aria-live={live ? "polite" : undefined}>
      <span className={styles.eyebrow}>{eyebrow}</span>
      <h1 className={styles.title}>{title}</h1>
      {copy ? <p className={styles.copy}>{copy}</p> : null}
      {plateTitle ? (
        <div className={styles.plate}>
          <span className={styles.number} aria-hidden="true">
            01
          </span>
          <div>
            <div className={styles.plateTitle}>{plateTitle}</div>
            {plateNote ? <div className={styles.plateNote}>{plateNote}</div> : null}
          </div>
        </div>
      ) : null}
      {progress ? <div className={styles.progress} role="progressbar" aria-label={title} /> : null}
      {primary ? (
        <a className={styles.primary} href={primary.href}>
          {primary.label}
          <span className={styles.arrow} aria-hidden="true">
            &rarr;
          </span>
        </a>
      ) : null}
      {secondary ? (
        <a className={styles.link} href={secondary.href}>
          {secondary.label}
        </a>
      ) : null}
    </section>
  );
}
