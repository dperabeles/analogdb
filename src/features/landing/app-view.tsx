"use client";

import type { AccessLang } from "@/features/auth/access-lang";
import { useInView } from "./motion";
import styles from "./landing.module.css";

export type AppScreen = "film-detail-inCamera" | "film-process" | "film-frames" | "inventory-film" | "stats-activity";

const SIZES: Record<AppScreen, [number, number]> = {
  "film-detail-inCamera": [478, 710],
  "film-process": [478, 710],
  "film-frames": [478, 458],
  "inventory-film": [478, 710],
  "stats-activity": [478, 640],
};

/// A real screen of the app, rendered from its Flutter widgets (light and
/// dark, Spanish and English) and shown on a registration plate. It opens
/// from the top like the app's wipe the first time it is seen.
export function AppView({
  screen,
  lang,
  caption,
  eager = false,
}: {
  screen: AppScreen;
  lang: AccessLang;
  caption: string;
  eager?: boolean;
}) {
  const [ref, seen] = useInView<HTMLElement>(0.2);
  const [w, h] = SIZES[screen];
  const base = `/app-views/${screen}-${lang}`;
  return (
    <figure className={styles.appView} ref={ref} data-in={seen}>
      <div className={styles.appViewFrame}>
        <picture>
          <source srcSet={`${base}-dark.png`} media="(prefers-color-scheme: dark)" />
          <img
            src={`${base}-light.png`}
            width={w}
            height={h}
            alt={caption}
            loading={eager ? "eager" : "lazy"}
            fetchPriority={eager ? "high" : undefined}
            decoding="async"
          />
        </picture>
      </div>
      <figcaption className={styles.appViewCaption}>{caption}</figcaption>
    </figure>
  );
}
