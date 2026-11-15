"use client";

import { useEffect, useRef, useState } from "react";
import { useInView } from "./motion";
import styles from "./landing.module.css";

type State = { key: string; label: string; note: string };

/// The app's status wipe (B) and tab rule (A): when the section is seen it
/// walks the roll once through its five states, then stops on the last one
/// and leaves the choice to the reader. Nothing loops.
export function RollStatus({ states, code }: { states: State[]; code: string }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.45);
  const [index, setIndex] = useState(0);
  const [previous, setPrevious] = useState(0);
  const touched = useRef(false);

  useEffect(() => {
    if (!seen) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let i = 0;
    const timer = window.setInterval(
      () => {
        if (touched.current || i >= states.length - 1) {
          window.clearInterval(timer);
          return;
        }
        i += 1;
        setPrevious(i - 1);
        setIndex(i);
      },
      reduce ? 1400 : 1100,
    );
    return () => window.clearInterval(timer);
  }, [seen, states.length]);

  function choose(i: number) {
    touched.current = true;
    setPrevious(index);
    setIndex(i);
  }

  const current = states[index];
  const forward = index >= previous;

  return (
    <div className={styles.status} ref={ref}>
      <div className={styles.statusPlate} data-state={current.key}>
        <span className={styles.statusCode}>{code}</span>
        <div className={styles.statusWipe}>
          {states.map((s, i) => (
            <span
              key={s.key}
              className={styles.statusFill}
              data-state={s.key}
              data-on={i === index}
              data-dir={forward ? "fwd" : "back"}
            >
              {s.label}
            </span>
          ))}
        </div>
        <p className={styles.statusNote} aria-live="polite">
          {current.note}
        </p>
      </div>

      <div className={styles.tabs} role="tablist" style={{ ["--n" as string]: states.length, ["--i" as string]: index }}>
        {states.map((s, i) => (
          <button
            key={s.key}
            type="button"
            role="tab"
            aria-selected={i === index}
            className={styles.tab}
            data-state={s.key}
            onClick={() => choose(i)}
          >
            <span className={styles.tabIndex}>{String(i + 1).padStart(2, "0")}</span>
            {s.label}
          </button>
        ))}
        <span className={styles.tabRule} data-state={current.key} aria-hidden="true" />
      </div>
    </div>
  );
}
