// send-push (ANA-74): delivers what the inbox queued in app_private.push_outbox.
//
// The database calls this after every hourly tick and after publishing a
// policy notice (app_private.push_flush), with the shared x-push-secret. It
// claims pending rows, decides per row (logic.ts), sends through FCM HTTP v1
// (fcm.ts) and reports back with push_complete. It reaches the database
// through the internal connection string Supabase gives every function.
import postgres from "npm:postgres@3.4.5";
import { buildMessage, type ClaimRow, classifyFcm, decide } from "./logic.ts";
import { googleBearer, safeEqual, sendFcm, type ServiceAccount } from "./fcm.ts";

const FIREBASE_PROJECT = "analog-archive-c184f";
const BATCH = 100;
const BUDGET_MS = 50_000;

type Sql = ReturnType<typeof postgres>;
type Outcome = "sent" | "failed" | "retry" | "opted_out" | "skipped" | "release";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function complete(
  sql: Sql,
  row: ClaimRow,
  outcome: Outcome,
  code: number | null = null,
  msg: { title: string; body: string } | null = null,
  clearToken = false,
): Promise<void> {
  await sql`select public.push_complete(${row.outbox_id}::uuid, ${outcome}, ${code}::int, ${msg?.title ?? null},
                                        ${msg?.body ?? null}, ${clearToken}, ${clearToken ? row.fcm_token : null})`;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("PUSH_FLUSH_SECRET") ?? "";
  if (!secret || !safeEqual(req.headers.get("x-push-secret") ?? "", secret)) {
    return json(401, { error: "unauthorized" });
  }
  const dbUrl = Deno.env.get("SUPABASE_DB_URL");
  if (!dbUrl) return json(500, { error: "missing_db_url" });

  const rawAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  let account: ServiceAccount | null = null;
  if (rawAccount) {
    try {
      account = JSON.parse(rawAccount) as ServiceAccount;
    } catch {
      console.error("send-push: FIREBASE_SERVICE_ACCOUNT is not valid JSON");
    }
  }

  const sql = postgres(dbUrl, { max: 1, prepare: false });
  const counts = { claimed: 0, sent: 0, waiting: 0, skipped: 0, failed: 0, retrying: 0 };
  const started = Date.now();
  let bearer: string | null = null;

  try {
    while (Date.now() - started < BUDGET_MS) {
      const rows = await sql<ClaimRow[]>`select * from public.push_claim(${BATCH}::int)`;
      counts.claimed += rows.length;
      let settled = 0;

      for (const row of rows) {
        const now = new Date();
        const decision = decide(now, row);
        const msg = buildMessage(row);

        if (decision === "wait") {
          await complete(sql, row, "release");
          counts.waiting++;
          continue;
        }
        if (decision === "skip_opted_out") {
          await complete(sql, row, "opted_out", null, msg);
          counts.skipped++;
          settled++;
          continue;
        }
        if (decision !== "send" || !msg || !row.fcm_token) {
          await complete(sql, row, "skipped");
          counts.skipped++;
          settled++;
          continue;
        }
        if (!account) {
          // Not configured in this environment yet: keep it for later.
          await complete(sql, row, "release");
          counts.waiting++;
          continue;
        }

        try {
          bearer ??= await googleBearer(account);
        } catch (e) {
          console.error("send-push: oauth failed", (e as Error).message);
          await complete(sql, row, "retry", null, msg);
          counts.retrying++;
          settled++;
          continue;
        }

        let result: { status: number; body: unknown };
        try {
          result = await sendFcm(bearer, FIREBASE_PROJECT, row.fcm_token, msg, row.kind);
        } catch {
          result = { status: 0, body: null };
        }
        const verdict = classifyFcm(result.status, result.body);
        if (verdict === "sent") {
          await complete(sql, row, "sent", result.status, msg);
          counts.sent++;
        } else if (verdict === "dead_token") {
          await complete(sql, row, "failed", result.status, msg, true);
          counts.failed++;
        } else {
          await complete(sql, row, "retry", result.status, msg);
          counts.retrying++;
        }
        settled++;
      }

      // A short batch means the queue is empty; a batch with nothing settled
      // would only hand the same rows back.
      if (rows.length < BATCH || settled === 0) break;
    }
  } catch (e) {
    console.error("send-push: failed", (e as Error).message);
    return json(500, { error: "failed", ...counts });
  } finally {
    await sql.end({ timeout: 5 });
  }

  return json(200, counts);
});
