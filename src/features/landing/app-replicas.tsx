"use client";

import { useEffect, useState } from "react";
import type { LandingCopy } from "./landing-copy";
import { RollingNumber, useInView } from "./motion";
import r from "./app-replicas.module.css";

/// Pieces of the app rebuilt in HTML with the app's own measures
/// (contacto_film_detail_view.dart, contacto_exposure_view.dart, the
/// inventory and stats views) and the gallery's sample roll. They are not
/// screenshots: they follow the page's theme and language and move the
/// way the app moves, once, when they are seen.

type App = LandingCopy["app"];
const STATUS = ["camera", "pending", "lab", "developed", "archived"] as const;

/* ---------- the roll's page: hero, readings and frame progress ---------- */

const TOTAL = 36;
const COUNT = 12;

export function FilmCard({ a }: { a: App }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.25);
  return (
    <div className={r.card} ref={ref} data-in={seen}>
      <div className={r.hero}>
        <div className={r.heroTop}>
          <span className={r.crumb} aria-hidden="true">
            {a.film} / R012
          </span>
          <span className={r.tag} data-state="camera">
            {a.status[0]}
          </span>
        </div>
        <div className={r.codeRow}>
          <span className={r.code}>R012</span>
          <span className={r.started}>
            <span>{a.startValue}</span>
            <span className={r.startedLabel}>{a.startDate}</span>
          </span>
        </div>
        <div className={r.filmName}>
          Kodak Portra
          <br />
          400
        </div>
        <div className={r.gear}>{a.gear}</div>
      </div>

      <div className={r.readings}>
        {[
          [a.exp, "36"],
          [a.iso, "400"],
          [a.pushPull, "—"],
        ].map(([label, value]) => (
          <div className={r.reading} key={label}>
            <span className={r.label}>{label}</span>
            <span className={r.readingValue}>{value}</span>
          </div>
        ))}
      </div>

      <div className={r.progress}>
        <div>
          <div className={r.count} aria-label={`${COUNT} / ${TOTAL}`}>
            <RollingNumber value={COUNT} />
            <span className={r.countOf}> / {TOTAL}</span>
          </div>
          <div className={r.countNote}>
            {a.registered}
            <br />
            {a.percent}
          </div>
        </div>
        {/* E: the logged frames enter in order, the newest in the accent */}
        <div className={r.matrix} aria-hidden="true">
          {Array.from({ length: TOTAL }, (_, i) => (
            <span
              key={i}
              className={r.dot}
              data-filled={i < COUNT}
              data-current={i === COUNT - 1}
              style={{ transitionDelay: i < COUNT ? `${Math.min(i * 40, 560)}ms` : undefined }}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

/* ---------- Ficha / Proceso / Fotogramas tabs ---------- */

export function FilmTabs({ a, selected }: { a: App; selected: 0 | 1 | 2 }) {
  return (
    <div className={r.filmTabs} style={{ ["--i" as string]: selected }}>
      {a.tabs.map((tab, i) => (
        <span key={tab} className={r.filmTab} data-tab={i} data-on={i === selected}>
          {tab}
        </span>
      ))}
      <span className={r.filmTabRule} data-tab={selected} aria-hidden="true" />
    </div>
  );
}

/* ---------- Proceso ---------- */

const LAB = 2; // the sample roll is at the lab

export function ProcessCard({ a }: { a: App }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.35);
  // B: once seen, the roll walks from «En cámara» to «En lab», one stage
  // at a time, each square filling with a sweep in its colour.
  const [reached, setReached] = useState(0);
  useEffect(() => {
    if (!seen) return;
    let step = 0;
    const timer = window.setInterval(() => {
      step += 1;
      setReached(step);
      if (step >= LAB) window.clearInterval(timer);
    }, 420);
    return () => window.clearInterval(timer);
  }, [seen]);

  return (
    <div className={r.card} ref={ref}>
      <FilmTabs a={a} selected={1} />
      <div className={r.stages}>
        {STATUS.map((key, i) => (
          <div className={r.stage} key={key}>
            <span className={r.stageBox} data-state={key} data-reached={i <= reached} data-current={i === reached}>
              <span className={r.stageFill} />
              <span className={r.stageNo}>{String(i + 1).padStart(2, "0")}</span>
            </span>
            <span className={r.stageLabel}>{a.status[i]}</span>
            <span className={r.stageMeta}>
              {i === 0 ? a.startValue : i === reached ? a.current : i < reached ? a.completed : "—"}
            </span>
          </div>
        ))}
      </div>
      <div className={r.labs}>
        {a.devLab}
        <br />
        {a.scanLab}
      </div>
    </div>
  );
}

/* ---------- Fotogramas: the open frame and two closed ones ---------- */

function Glyph({ kind }: { kind: number }) {
  const common = { width: 14, height: 14, viewBox: "0 0 14 14", fill: "none", stroke: "currentColor", strokeWidth: 1.2 };
  switch (kind) {
    case 0:
      return (
        <svg {...common} aria-hidden="true">
          <path d="M8 1 3 8h4l-1 5 5-7H7l1-5Z" fill="currentColor" stroke="none" />
        </svg>
      );
    case 1:
      return (
        <svg {...common} aria-hidden="true">
          <path d="M2 2h10M7 2v4M7 6l-4 7M7 6v7M7 6l4 7" />
        </svg>
      );
    case 2:
      return (
        <svg {...common} aria-hidden="true">
          <circle cx="7" cy="7" r="5.5" />
          <circle cx="7" cy="7" r="2.8" />
        </svg>
      );
    case 3:
      return (
        <svg {...common} aria-hidden="true">
          <circle cx="7" cy="7" r="2.6" />
          <path d="M7 .8v2M7 11.2v2M.8 7h2M11.2 7h2M2.6 2.6 4 4M10 10l1.4 1.4M2.6 11.4 4 10M10 4l1.4-1.4" />
        </svg>
      );
    case 4:
      return (
        <svg {...common} aria-hidden="true">
          <circle cx="5.5" cy="7.5" r="3.8" />
          <circle cx="8.5" cy="5.5" r="3.8" />
        </svg>
      );
    default:
      return null;
  }
}

export function FramesCard({ a }: { a: App }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.3);
  return (
    <div className={r.card} ref={ref} data-in={seen}>
      <FilmTabs a={a} selected={2} />
      <div className={r.frames}>
        <div className={r.frameOpen}>
          <div className={r.frameHead}>
            <span className={r.frameNo}>01</span>
            <span className={r.frameTitle}>{a.settings}</span>
            <span className={r.frameArrow} data-open="true" aria-hidden="true">
              &darr;
            </span>
          </div>
          <div className={r.frameBody}>
            <div className={r.lensRow}>
              <span className={r.label}>{a.lens}</span>
              <span className={r.lensValue}>
                {a.lensValue}
                <span className={r.fromRoll}>{a.fromRoll}</span>
              </span>
              <span className={r.chevron} aria-hidden="true">
                &#8964;
              </span>
            </div>
            <div className={r.dials}>
              {[
                [a.aperture, "f/2.8"],
                [a.shutter, "1/250"],
              ].map(([label, value]) => (
                <div className={r.dial} key={label}>
                  <span className={r.label}>{label}</span>
                  <span className={r.dialValue}>
                    {value}
                    <span className={r.chevron} aria-hidden="true">
                      &#8964;
                    </span>
                  </span>
                </div>
              ))}
            </div>
            <div className={r.same}>&#8600; {a.sameAsBefore}</div>
            <div className={r.flags}>
              {a.flags.map((flag, i) => (
                <span className={r.flag} key={flag} data-on={i === 3}>
                  {i < 5 ? <Glyph kind={i} /> : null}
                  {flag}
                </span>
              ))}
            </div>
          </div>
        </div>
        {[
          ["02", "f/4", "1/125"],
          ["03", "f/4", "1/125"],
        ].map(([n, ap, sh]) => (
          <div className={r.frameClosed} key={n}>
            <span className={r.frameNo}>{n}</span>
            <span className={r.closedAperture}>{ap}</span>
            <span className={r.closedShutter}>{sh}</span>
            <span className={r.frameArrow} aria-hidden="true">
              &darr;
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/* ---------- Inventario: tabs, filter and two stock cards ---------- */

const INV_COLORS = ["accent", "camera", "pending", "lab"] as const;

export function InventoryCard({ a }: { a: App }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.3);
  return (
    <div className={r.card} ref={ref} data-in={seen}>
      <div className={r.invTabs}>
        {a.invTabs.map((tab, i) => (
          <span key={tab} className={r.invTab} data-color={INV_COLORS[i]} data-on={i === 0}>
            {tab}
            <span className={r.invCount}>{["08", "02", "03", "01"][i]}</span>
          </span>
        ))}
      </div>
      <div className={r.filter}>
        <span data-on="true">{a.all}</span>
        <span>35 mm</span>
        <span>120</span>
      </div>
      <div className={r.stockHead}>
        <span>{a.inStock}</span>
        <span>{a.inStockCount}</span>
      </div>
      {[
        { color: "accent", format: "35 mm", units: 7, note: a.freshExpired },
        { color: "camera", format: "120", units: 1, note: a.freshOnly },
      ].map((s, i) => (
        <div className={r.stock} key={s.format} style={{ transitionDelay: `${i * 60}ms` }}>
          <div className={r.stockBand} data-color={s.color}>
            <span>Kodak</span>
            <span className={r.stockFormat}>{s.format}</span>
          </div>
          <div className={r.stockBody}>
            <span className={r.stockName} data-color={s.color}>
              Gold 200
            </span>
            <span className={r.stockUnits}>
              <span className={r.stockArrow} aria-hidden="true">
                &#8599;
              </span>
              <span>
                <b>{s.units}</b> {s.units === 1 ? a.unit : a.units}
              </span>
            </span>
          </div>
          <div className={r.stockFoot}>
            <span>ISO 200</span>
            <span>{s.note}</span>
          </div>
          <div className={r.perforation} aria-hidden="true" />
        </div>
      ))}
    </div>
  );
}

/* ---------- Cifras: summary and the activity bars ---------- */

const BARS = [1, 2, 1, 0.05, 3, 2, 1, 2, 1, 3, 5, 3];

export function StatsCard({ a }: { a: App }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.3);
  return (
    <div className={r.card} ref={ref} data-in={seen}>
      <div className={r.summary}>
        <div className={r.summaryMain}>
          <RollingNumber value={24} className={r.summaryBig} />
          <span className={r.label}>{a.filmsInArchive}</span>
        </div>
        <div className={r.summarySide}>
          {[
            [720, a.frames],
            [21, a.thisYear],
          ].map(([value, label]) => (
            <div className={r.summaryRow} key={String(label)}>
              <RollingNumber value={Number(value)} className={r.summaryValue} />
              <span className={r.label}>{label}</span>
            </div>
          ))}
          <div className={r.summaryRow}>
            <span className={r.summaryValue}>4.3</span>
            <span className={r.label}>{a.rating}</span>
          </div>
        </div>
      </div>
      <div className={r.chartHead}>
        <span>
          <span className={r.chartIndex}>01 /</span> {a.activity}
        </span>
        <span className={r.label}>{a.months12}</span>
      </div>
      <div className={r.chartSub}>
        <span>{a.range}</span>
        <span>{a.lastMonth}</span>
      </div>
      {/* D: bars grow from the base, 30 ms apart */}
      <div className={r.chart} aria-hidden="true">
        {BARS.map((v, i) => (
          <span
            key={i}
            className={r.bar}
            data-last={i === BARS.length - 1}
            style={{ height: `${(v / 5) * 100}%`, transitionDelay: `${i * 30}ms` }}
          />
        ))}
      </div>
      <div className={r.months} aria-hidden="true">
        {a.monthLetters.map((m, i) => (
          <span key={i}>{m}</span>
        ))}
      </div>
    </div>
  );
}
