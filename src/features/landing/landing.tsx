import type { AccessLang } from "@/features/auth/access-lang";
import { Mark, instrument } from "@/features/auth/contacto-access";
import { ContactSheet } from "./contact-sheet";
import { LandingAccess } from "./landing-access";
import type { LandingCopy } from "./landing-copy";
import { Reveal, RollingNumber } from "./motion";
import { RollStatus } from "./roll-status";
import styles from "./landing.module.css";

export type LandingMetrics = {
  totalRolls: number;
  topStockLabel: string;
  topStockCount: number;
  uniqueLocations: number;
  supportedFormats: number;
};

function SectionHead({ index, section, title }: { index: string; section: string; title: string }) {
  return (
    <header className={styles.sectionHead}>
      <span className={styles.sectionIndex} aria-hidden="true">
        {index}
      </span>
      <span className={styles.sectionName}>{section}</span>
      <h2 className={styles.sectionTitle}>{title}</h2>
    </header>
  );
}

/// The home page in Contacto v38: a contact sheet of the product. Each
/// section is a numbered frame; motion follows the app (cascade, wipe,
/// tab rule, rolling numbers, growing bars) and plays once.
export function Landing({ t, lang, metrics }: { t: LandingCopy; lang: AccessLang; metrics: LandingMetrics | null }) {
  const other = lang === "es" ? "en" : "es";
  const costTotal = t.inventory.costs.reduce((sum, c) => sum + c.value, 0);
  const maxCost = Math.max(...t.inventory.costs.map((c) => c.value));

  return (
    <div className={`${styles.landing} ${instrument.variable}`} lang={lang}>
      <div className={styles.dots} aria-hidden="true" />

      <header className={styles.top}>
        <a className={styles.brand} href={lang === "es" ? "/" : "/?lang=en"} aria-label="analog archive">
          <span className={styles.brandMark}>
            <Mark />
          </span>
          <span className={styles.brandWord}>
            analog
            <br />
            archive
          </span>
        </a>
        <nav className={styles.topNav}>
          <a href={`/?lang=${other}`} hrefLang={other} aria-label={t.nav.switchLabel} className={styles.lang}>
            {t.nav.switchLang}
          </a>
          <a href="#acceso" className={styles.enter}>
            {t.nav.enter} <span aria-hidden="true">&#8599;</span>
          </a>
        </nav>
      </header>

      <main>
        {/* hero */}
        <section className={styles.hero}>
          <div className={styles.heroCopy}>
            <span className={`${styles.eyebrow} ${styles.enter1}`}>{t.hero.eyebrow}</span>
            <h1 className={`${styles.heroTitle} ${styles.enter2}`}>
              {t.hero.title.map((line, i) => (
                <span key={i} className={styles.heroLine}>
                  {line}
                  {i === t.hero.title.length - 1 ? <em className={styles.accent}>{t.hero.titleAccent}</em> : null}
                </span>
              ))}
            </h1>
            <p className={`${styles.copy} ${styles.enter3}`}>{t.hero.copy}</p>
            <div className={`${styles.heroActions} ${styles.enter4}`}>
              <a className={styles.primary} href="#proceso">
                {t.hero.primary}
                <span className={styles.arrow} aria-hidden="true">
                  &darr;
                </span>
              </a>
              <div className={styles.miniPlate}>
                <span className={styles.miniPlateNo} aria-hidden="true">
                  01
                </span>
                <div>
                  <div className={styles.plateTitle}>{t.hero.platePlatform}</div>
                  <div className={styles.plateNote}>{t.hero.plateNote}</div>
                </div>
              </div>
            </div>
          </div>
          <ContactSheet label={t.hero.sheetLabel} caption="R024 · KODAK GOLD 200" />
        </section>

        {/* 01 process */}
        <section className={styles.section} id="proceso">
          <Reveal>
            <SectionHead index={t.process.index} section={t.process.section} title={t.process.title} />
            <p className={styles.copy}>{t.process.copy}</p>
          </Reveal>
          <Reveal delay={60}>
            <RollStatus states={t.process.states} code="R024" />
          </Reveal>
        </section>

        {/* 02 frames */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.frames.index} section={t.frames.section} title={t.frames.title} />
            <p className={styles.copy}>{t.frames.copy}</p>
          </Reveal>
          <ol className={styles.frameRows}>
            {t.frames.rows.map((row, i) => (
              <li key={row.n}>
                <Reveal delay={i * 60} className={styles.frameRow}>
                  <span className={styles.frameRowNo} aria-hidden="true">
                    {row.n}
                  </span>
                  <span className={styles.frameRowData}>{row.data}</span>
                  <span className={styles.frameRowNote}>{row.note}</span>
                  <span className={styles.frameRowArrow} aria-hidden="true">
                    &#8599;
                  </span>
                </Reveal>
              </li>
            ))}
          </ol>
        </section>

        {/* 03 inventory and costs */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.inventory.index} section={t.inventory.section} title={t.inventory.title} />
            <p className={styles.copy}>{t.inventory.copy}</p>
          </Reveal>
          <div className={styles.inventory}>
            <Reveal className={styles.stockCard}>
              <div className={styles.stockHead}>
                <span className={styles.stockSwatch} aria-hidden="true" />
                <div>
                  <div className={styles.stockName}>{t.inventory.stock}</div>
                  <div className={styles.plateNote}>{t.inventory.format}</div>
                </div>
              </div>
              <div className={styles.stockSplit}>
                <div>
                  <RollingNumber value={3} className={styles.stockCount} />
                  <span className={styles.stockLabel}>{t.inventory.fresh}</span>
                </div>
                <div>
                  <RollingNumber value={1} className={styles.stockCount} />
                  <span className={styles.stockLabel}>{t.inventory.expired}</span>
                </div>
              </div>
            </Reveal>
            <Reveal delay={80} className={styles.costs}>
              {t.inventory.costs.map((c, i) => (
                <div className={styles.costRow} key={c.label}>
                  <span className={styles.costLabel}>{c.label}</span>
                  <span className={styles.costBar} aria-hidden="true">
                    <span style={{ ["--w" as string]: `${(c.value / maxCost) * 100}%`, transitionDelay: `${i * 30}ms` }} />
                  </span>
                  <span className={styles.costValue}>
                    $<RollingNumber value={c.value} />
                  </span>
                </div>
              ))}
              <div className={styles.costTotal}>
                <span>{t.inventory.costTotal}</span>
                <span>
                  $<RollingNumber value={costTotal} /> <small>{t.inventory.currency}</small>
                </span>
              </div>
            </Reveal>
          </div>
        </section>

        {/* 04 numbers */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.numbers.index} section={t.numbers.section} title={t.numbers.title} />
            <p className={styles.copy}>{t.numbers.copy}</p>
          </Reveal>
          <div className={styles.metrics}>
            <Reveal className={styles.metric}>
              <RollingNumber value={metrics?.totalRolls ?? 0} className={styles.metricValue} />
              <span className={styles.metricLabel}>{t.numbers.rolls}</span>
            </Reveal>
            <Reveal delay={40} className={styles.metric}>
              <span className={styles.metricWord}>{metrics?.topStockLabel ?? "—"}</span>
              <span className={styles.metricLabel}>
                {t.numbers.top}
                {metrics ? ` · ${metrics.topStockCount} ${t.numbers.topSuffix}` : ""}
              </span>
            </Reveal>
            <Reveal delay={80} className={styles.metric}>
              <RollingNumber value={metrics?.uniqueLocations ?? 0} className={styles.metricValue} />
              <span className={styles.metricLabel}>{t.numbers.places}</span>
            </Reveal>
            <Reveal delay={120} className={styles.metric}>
              <RollingNumber value={metrics?.supportedFormats ?? 6} className={styles.metricValue} />
              <span className={styles.metricLabel}>
                {t.numbers.formats}
                <span className={styles.metricNote}>{t.numbers.formatsNote}</span>
              </span>
            </Reveal>
          </div>
        </section>

        {/* 05 privacy */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.privacy.index} section={t.privacy.section} title={t.privacy.title} />
          </Reveal>
          <ul className={styles.privacyList}>
            {t.privacy.lines.map((line, i) => (
              <li key={line}>
                <Reveal delay={i * 60} className={styles.privacyRow}>
                  <span className={styles.privacyMark} aria-hidden="true">
                    +
                  </span>
                  {line}
                </Reveal>
              </li>
            ))}
          </ul>
        </section>

        {/* 06 access */}
        <section className={`${styles.section} ${styles.accessSection}`} id="acceso">
          <Reveal>
            <SectionHead index={t.access.index} section={t.access.section} title={t.access.title} />
          </Reveal>
          <Reveal delay={60}>
            <LandingAccess copy={t.access} lang={lang} />
          </Reveal>
        </section>
      </main>

      <footer className={styles.footer}>
        <div className={styles.edge} aria-hidden="true">
          ANALOG ARCHIVE 200 &nbsp;&#9656; 36 &nbsp;&#9656; 36A &nbsp;&nbsp; ANALOG ARCHIVE 200 &nbsp;&#9656; 1 &nbsp;&#9656; 1A
        </div>
        <nav className={styles.footerNav}>
          <a href="/privacy">{t.footer.privacy}</a>
          <a href="/terms">{t.footer.terms}</a>
          <a href="/cookies">{t.footer.cookies}</a>
          <a href="/contact">{t.footer.contact}</a>
          <a href="mailto:hello@analog-archive.com">hello@analog-archive.com</a>
          <a href="https://instagram.com/analog.archive.app" target="_blank" rel="noopener noreferrer">
            @analog.archive.app
          </a>
        </nav>
        <p className={styles.footerBy}>
          {t.footer.by}{" "}
          <a
            href="https://www.instagram.com/perabeles.jpg?igsh=MXg1dXczaDgwaWJobg%3D%3D&utm_source=qr"
            target="_blank"
            rel="noopener noreferrer"
          >
            Diego Perabeles
          </a>{" "}
          · {t.footer.place} · © {new Date().getFullYear()}
        </p>
      </footer>
    </div>
  );
}
