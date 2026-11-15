"use client";

import { useEffect, useState } from "react";
import { RollingNumber, useInView } from "./motion";
import styles from "./landing.module.css";

const TOTAL = 36;
const SHOT = 24;

/// Deterministic tones so every visit shows the same roll: two values per
/// frame, a sky and a ground, like a small print seen from a distance.
function tone(i: number) {
  const a = Math.sin(i * 12.9898) * 43758.5453;
  const r = a - Math.floor(a);
  const b = Math.sin(i * 78.233) * 12345.6789;
  const s = b - Math.floor(b);
  const top = 30 + Math.round(r * 46);
  const bottom = 18 + Math.round(s * 40);
  const split = 38 + Math.round(((r + s) / 2) * 34);
  // Gold 200 runs warm: skies lean cream, grounds lean amber and brown.
  const warm = 16 + Math.round(r * 18);
  const sky = 34 + Math.round(s * 14);
  return `linear-gradient(180deg, hsl(${sky} ${warm}% ${top + 8}%) 0%, hsl(${sky} ${warm - 4}% ${top}%) ${split}%, hsl(26 ${warm + 8}% ${bottom}%) ${split}%, hsl(22 ${warm + 4}% ${bottom + 10}%) 100%)`;
}

/// Hero: a 36-exposure contact sheet. The 24 logged frames enter in a
/// cascade (the app's frame matrix), frame 25 is the current one, the rest
/// are still unexposed; the counter rolls to 24 once the sheet is seen.
export function ContactSheet({ label, caption }: { label: string; caption: string }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.2);
  const [settled, setSettled] = useState(false);
  useEffect(() => {
    if (!seen) return;
    const t = window.setTimeout(() => setSettled(true), 650);
    return () => window.clearTimeout(t);
  }, [seen]);

  return (
    <figure className={styles.sheet} ref={ref} data-in={seen} aria-label={label}>
      {[0, 1, 2, 3, 4, 5].map((strip) => (
        <div className={styles.strip} key={strip} aria-hidden="true">
          <div className={styles.sprockets} />
          <div className={styles.stripFrames}>
            {Array.from({ length: 6 }, (_, k) => {
              const i = strip * 6 + k;
              const n = i + 1;
              const state = n <= SHOT ? "shot" : n === SHOT + 1 ? "current" : "blank";
              return (
                <div className={styles.frameCell} key={n}>
                  <div
                    className={styles.frame}
                    data-state={state}
                    style={{
                      background: state === "shot" ? tone(n) : undefined,
                      transitionDelay: seen && state === "shot" ? `${Math.min(i * 22, 520)}ms` : undefined,
                    }}
                  />
                  <span className={styles.frameNo}>
                    {n}
                    {n % 2 === 0 ? "A" : ""}
                  </span>
                </div>
              );
            })}
          </div>
          <div className={styles.sprockets} />
        </div>
      ))}
      <figcaption className={styles.sheetCaption}>
        <span>{caption}</span>
        <span className={styles.sheetCount} data-settled={settled}>
          <RollingNumber value={SHOT} />
          <span className={styles.sheetOf}>/{TOTAL}</span>
        </span>
      </figcaption>
    </figure>
  );
}
