import { assertEquals } from "jsr:@std/assert@1.0.13";
import { buildMessage, type ClaimRow, classifyFcm, decide, isStale, isWithinHours } from "./logic.ts";

const MX = "America/Mexico_City";

function row(over: Partial<ClaimRow> = {}): ClaimRow {
  return {
    outbox_id: "o1",
    user_id: "u1",
    kind: "develop_reminder",
    rang_at: "2026-11-16T15:00:00Z",
    attempts: 0,
    fcm_token: "tok",
    fcm_platform: "ios",
    locale: "es",
    zone: MX,
    legal_updates: true,
    develop_count: 1,
    title_es: null,
    title_en: null,
    summary_es: null,
    summary_en: null,
    ...over,
  };
}

Deno.test("isWithinHours: 08:00 to 21:59 local", () => {
  assertEquals(isWithinHours(new Date("2026-11-16T14:00:00Z"), MX), true); // 08:00
  assertEquals(isWithinHours(new Date("2026-11-16T13:59:00Z"), MX), false); // 07:59
  assertEquals(isWithinHours(new Date("2026-11-17T03:59:00Z"), MX), true); // 21:59
  assertEquals(isWithinHours(new Date("2026-11-17T04:00:00Z"), MX), false); // 22:00
});

Deno.test("isWithinHours: an unknown zone falls back to Mexico City", () => {
  assertEquals(isWithinHours(new Date("2026-11-16T14:00:00Z"), "Not/AZone"), true);
  assertEquals(isWithinHours(new Date("2026-11-16T13:59:00Z"), "Not/AZone"), false);
});

Deno.test("isStale: more than 24 hours", () => {
  const rang = new Date("2026-11-16T15:00:00Z");
  assertEquals(isStale(new Date(rang.getTime() + 24 * 3600e3 + 1000), rang), true);
  assertEquals(isStale(new Date(rang.getTime() + 23 * 3600e3), rang), false);
});

Deno.test("buildMessage: develop reminder in the account's language", () => {
  assertEquals(buildMessage(row()), { title: "Tu siguiente revelado.", body: "Tienes 1 film por revelar." });
  assertEquals(buildMessage(row({ develop_count: 3 })), {
    title: "Tu siguiente revelado.",
    body: "Tienes 3 films por revelar.",
  });
  assertEquals(buildMessage(row({ develop_count: 3, locale: "en-US" })), {
    title: "Your next development.",
    body: "You have 3 films to develop.",
  });
  assertEquals(buildMessage(row({ develop_count: 1, locale: "en" })), {
    title: "Your next development.",
    body: "You have 1 film to develop.",
  });
});

Deno.test("buildMessage: nothing to say when no roll is waiting any more", () => {
  assertEquals(buildMessage(row({ develop_count: 0 })), null);
  assertEquals(buildMessage(row({ develop_count: null })), null);
});

Deno.test("buildMessage: policy notice uses its own title and summary", () => {
  const p = row({
    kind: "policy_change",
    develop_count: null,
    title_es: "Cambios",
    title_en: "Changes",
    summary_es: "Resumen",
    summary_en: "Summary",
  });
  assertEquals(buildMessage(p), { title: "Cambios", body: "Resumen" });
  assertEquals(buildMessage({ ...p, locale: "en-GB" }), { title: "Changes", body: "Summary" });
  assertEquals(buildMessage({ ...p, title_es: null }), null);
});

Deno.test("decide", () => {
  const day = new Date("2026-11-16T18:00:00Z"); // 12:00 in Mexico City
  const night = new Date("2026-11-17T08:00:00Z"); // 02:00
  assertEquals(decide(day, row()), "send");
  assertEquals(decide(day, row({ fcm_token: null })), "skip_no_token");
  assertEquals(decide(day, row({ kind: "policy_change", legal_updates: false })), "skip_opted_out");
  assertEquals(decide(night, row()), "wait");
  assertEquals(decide(new Date("2026-11-18T08:00:00Z"), row()), "skip_stale"); // stale wins at night
  assertEquals(decide(day, row({ develop_count: 0 })), "skip_empty");
});

Deno.test("classifyFcm", () => {
  assertEquals(classifyFcm(200, {}), "sent");
  assertEquals(classifyFcm(404, { error: { details: [{ errorCode: "UNREGISTERED" }] } }), "dead_token");
  assertEquals(classifyFcm(400, { error: { details: [{ errorCode: "INVALID_ARGUMENT" }] } }), "dead_token");
  assertEquals(classifyFcm(400, { error: { details: [{ errorCode: "SENDER_ID_MISMATCH" }] } }), "dead_token");
  assertEquals(classifyFcm(503, {}), "retry");
  assertEquals(classifyFcm(401, {}), "retry");
  assertEquals(classifyFcm(429, null), "retry");
});
