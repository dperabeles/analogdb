"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import styles from "./landing.module.css";

/// The app's motion vocabulary (AnalogMotion): 180 ms marks, 280 ms space,
/// 400 ms entrances, one ease-out curve, never longer than 600 ms. Reduced
/// motion turns everything into a short fade (see landing.module.css).

/// True once the element has entered the viewport; never goes back.
export function useInView<T extends Element>(threshold = 0.25) {
  const ref = useRef<T>(null);
  const [seen, setSeen] = useState(false);
  useEffect(() => {
    const node = ref.current;
    if (!node || seen) return;
    if (typeof IntersectionObserver === "undefined") {
      setSeen(true);
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setSeen(true);
          observer.disconnect();
        }
      },
      { threshold },
    );
    observer.observe(node);
    return () => observer.disconnect();
  }, [seen, threshold]);
  return [ref, seen] as const;
}

/// A block that rises 24 px and fades in once, when it enters.
export function Reveal({ children, delay = 0, className = "" }: { children: ReactNode; delay?: number; className?: string }) {
  const [ref, seen] = useInView<HTMLDivElement>(0.15);
  return (
    <div
      ref={ref}
      className={`${styles.reveal} ${className}`}
      data-in={seen}
      style={{ transitionDelay: seen ? `${delay}ms` : undefined }}
    >
      {children}
    </div>
  );
}

/// The app's RollInNumber: each digit rolls up from 0 once it is seen.
/// Tabular figures keep the width still; screen readers get the value once.
export function RollingNumber({ value, className = "" }: { value: number; className?: string }) {
  const [ref, seen] = useInView<HTMLSpanElement>(0.4);
  const digits = String(Math.max(0, Math.round(value))).split("");
  return (
    <span ref={ref} className={`${styles.rolling} ${className}`} aria-label={String(value)} role="img">
      {digits.map((d, i) => (
        <span key={i} className={styles.digit} aria-hidden="true">
          <span
            className={styles.digitStrip}
            style={{
              transform: `translateY(${seen ? -Number(d) * 10 : 0}%)`,
              transitionDelay: `${(digits.length - 1 - i) * 40}ms`,
            }}
          >
            {"0123456789".split("").map((n) => (
              <span key={n}>{n}</span>
            ))}
          </span>
        </span>
      ))}
    </span>
  );
}
