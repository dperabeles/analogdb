// Pure decisions for send-push (ANA-74). No I/O here, so it is all testable.

export type ClaimRow = {
  outbox_id: string;
  user_id: string;
  kind: "develop_reminder" | "policy_change";
  rang_at: string;
  attempts: number;
  fcm_token: string | null;
  fcm_platform: string | null;
  locale: string;
  zone: string;
  legal_updates: boolean;
  develop_count: number | null;
  title_es: string | null;
  title_en: string | null;
  summary_es: string | null;
  summary_en: string | null;
};

export type Decision = "send" | "wait" | "skip_stale" | "skip_no_token" | "skip_opted_out" | "skip_empty";

const FALLBACK_ZONE = "America/Mexico_City";
const DAY_MS = 24 * 3600 * 1000;

function localMinutes(now: Date, zone: string): number {
  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat("en-GB", { timeZone: zone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .formatToParts(now);
  } catch {
    parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: FALLBACK_ZONE,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(now);
  }
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? "0");
  return get("hour") * 60 + get("minute");
}

/** 08:00 to 21:59 in the account's zone. */
export function isWithinHours(now: Date, zone: string): boolean {
  const m = localMinutes(now, zone);
  return m >= 8 * 60 && m < 22 * 60;
}

/** A ring older than a day is no longer worth a notification. */
export function isStale(now: Date, rangAt: Date): boolean {
  return now.getTime() - rangAt.getTime() > DAY_MS;
}

function english(locale: string): boolean {
  return locale.toLowerCase().startsWith("en");
}

/** Same copy as the inbox. Never roll codes, names or notes. */
export function buildMessage(row: ClaimRow): { title: string; body: string } | null {
  const en = english(row.locale);
  if (row.kind === "develop_reminder") {
    const n = row.develop_count ?? 0;
    if (n < 1) return null;
    return en
      ? { title: "Your next development.", body: n === 1 ? "You have 1 film to develop." : `You have ${n} films to develop.` }
      : { title: "Tu siguiente revelado.", body: n === 1 ? "Tienes 1 film por revelar." : `Tienes ${n} films por revelar.` };
  }
  const title = en ? row.title_en : row.title_es;
  const body = en ? row.summary_en : row.summary_es;
  if (!title || !body) return null;
  return { title, body };
}

export function decide(now: Date, row: ClaimRow): Decision {
  if (isStale(now, new Date(row.rang_at))) return "skip_stale";
  if (!row.fcm_token) return "skip_no_token";
  if (row.kind === "policy_change" && !row.legal_updates) return "skip_opted_out";
  if (buildMessage(row) === null) return "skip_empty";
  if (!isWithinHours(now, row.zone)) return "wait";
  return "send";
}

const DEAD_TOKEN_CODES = new Set(["UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"]);

/** FCM HTTP v1 response → what to do with the row and the token. */
export function classifyFcm(status: number, body: unknown): "sent" | "dead_token" | "retry" {
  if (status >= 200 && status < 300) return "sent";
  const details = (body as { error?: { details?: { errorCode?: string }[] } } | null)?.error?.details ?? [];
  if (details.some((d) => d.errorCode && DEAD_TOKEN_CODES.has(d.errorCode))) return "dead_token";
  if (status === 404) return "dead_token";
  return "retry";
}
