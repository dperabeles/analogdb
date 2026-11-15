import type { Metadata } from "next";
import { type AccessPageProps, accessLangFor } from "@/features/auth/access-lang-server";
import { Landing, type LandingMetrics } from "@/features/landing/landing";
import { LANDING_COPY } from "@/features/landing/landing-copy";
import { publicEnv } from "@/lib/env";

export async function generateMetadata(props: AccessPageProps): Promise<Metadata> {
  const t = LANDING_COPY[await accessLangFor(props)];
  return { title: t.meta.title, description: t.meta.description };
}

/// Public counts for the home page, refreshed every five minutes. A failure
/// only hides the live numbers; the page never waits on them for long.
async function loadMetrics(): Promise<LandingMetrics | null> {
  if (!publicEnv.supabaseUrl || !publicEnv.supabaseAnonKey) return null;
  try {
    const res = await fetch(`${publicEnv.supabaseUrl}/rest/v1/rpc/landing_metrics`, {
      method: "POST",
      headers: { apikey: publicEnv.supabaseAnonKey, "Content-Type": "application/json" },
      body: "{}",
      next: { revalidate: 300 },
      signal: AbortSignal.timeout(2500),
    });
    if (!res.ok) return null;
    const raw = (await res.json()) as unknown;
    const record = (Array.isArray(raw) ? raw[0] : raw) as Record<string, unknown> | null;
    const v = (record && "landing_metrics" in record ? record.landing_metrics : record) as Record<string, unknown> | null;
    if (!v) return null;
    return {
      totalRolls: Number(v.totalRolls || 0),
      topStockLabel: String(v.topStockLabel || "—"),
      topStockCount: Number(v.topStockCount || 0),
      uniqueLocations: Number(v.uniqueLocations || 0),
      supportedFormats: Number(v.supportedFormats || 6),
    };
  } catch {
    return null;
  }
}

export default async function HomePage(props: AccessPageProps) {
  const lang = await accessLangFor(props);
  const metrics = await loadMetrics();
  return <Landing t={LANDING_COPY[lang]} lang={lang} metrics={metrics} />;
}
