import type { AccessLang } from "@/features/auth/access-lang";
import { Mark, instrument } from "@/features/auth/contacto-access";
import { CamerasCard, FilmCard, FramesCard, InventoryCard, ProcessCard, StatsCard } from "./app-replicas";
import type { LandingCopy } from "./landing-copy";
import { Reveal, RollingNumber } from "./motion";
import styles from "./landing.module.css";

export type LandingMetrics = {
  totalRolls: number;
  topStockLabel: string;
  topStockCount: number;
  uniqueLocations: number;
  supportedFormats: number;
};

/// A check drawn in CSS, never a font glyph or an emoji; read as «Incluido».
function Check({ label }: { label: string }) {
  return <span className={styles.check} role="img" aria-label={label} />;
}

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
          {/* The web app is paused (Diego, 17-nov): «Entrar» stays, inactive. */}
          <span className={styles.soon} aria-disabled="true">
            {t.nav.webapp}
          </span>
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
          <FilmCard a={t.app} />
        </section>

        {/* 01 process */}
        <section className={styles.section} id="proceso">
          <Reveal>
            <SectionHead index={t.process.index} section={t.process.section} title={t.process.title} />
            <p className={styles.copy}>{t.process.copy}</p>
          </Reveal>
          <ProcessCard a={t.app} />
        </section>

        {/* 02 frames */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.frames.index} section={t.frames.section} title={t.frames.title} />
            <p className={styles.copy}>{t.frames.copy}</p>
          </Reveal>
          <FramesCard a={t.app} />
        </section>

        {/* 03 inventory and costs */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.inventory.index} section={t.inventory.section} title={t.inventory.title} />
            <p className={styles.copy}>{t.inventory.copy}</p>
          </Reveal>
          <InventoryCard a={t.app} />
        </section>

        {/* gear: the Cámaras tab of the inventory */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.gear.index} section={t.gear.section} title={t.gear.title} />
            <p className={styles.copy}>{t.gear.copy}</p>
          </Reveal>
          <CamerasCard a={t.app} />
        </section>

        {/* numbers: the app's own numbers, then the live counts across */}
        <section className={styles.section}>
          <Reveal>
            <SectionHead index={t.numbers.index} section={t.numbers.section} title={t.numbers.title} />
          </Reveal>
          <StatsCard a={t.app} />
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

        {/* 07 pricing: free and Pro, no price until the store has one */}
        <section className={styles.section} id="precios">
          <Reveal>
            <SectionHead index={t.pricing.index} section={t.pricing.section} title={t.pricing.title} />
          </Reveal>
          <Reveal delay={60}>
            <table className={styles.priceTable}>
              <thead>
                <tr>
                  <th scope="col">
                    <span className={styles.srOnly}>{t.pricing.section}</span>
                  </th>
                  <th scope="col">{t.pricing.free}</th>
                  <th scope="col" className={styles.priceHeadPro}>
                    {t.pricing.pro}
                  </th>
                </tr>
              </thead>
              <tbody>
                {t.pricing.rows.map((row) => (
                  <tr key={row.label}>
                    <th scope="row">{row.label}</th>
                    <td>{row.free ? <Check label={t.pricing.included} /> : null}</td>
                    <td>
                      <Check label={t.pricing.included} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className={styles.sectionNote}>{t.pricing.note}</p>
          </Reveal>
        </section>

        {/* 08 on the way: intentions, without dates */}
        <section className={styles.section} id="en-camino">
          <Reveal>
            <SectionHead index={t.roadmap.index} section={t.roadmap.section} title={t.roadmap.title} />
          </Reveal>
          <div>
            <ul className={styles.privacyList}>
              {t.roadmap.items.map((item, i) => (
                <li key={item.name}>
                  <Reveal delay={i * 60} className={styles.roadmapRow}>
                    <span className={styles.roadmapName}>{item.name}</span>
                    <span className={styles.roadmapCopy}>{item.copy}</span>
                  </Reveal>
                </li>
              ))}
            </ul>
          </div>
        </section>
      </main>

      <footer className={styles.footer}>
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
