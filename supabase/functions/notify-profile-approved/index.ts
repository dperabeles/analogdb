type ProfileRecord = {
  user_id?: string;
  email?: string;
  display_name?: string;
  status?: string;
  approved_at?: string;
};

type ProfileStatusPayload = {
  type?: string;
  schema?: string;
  table?: string;
  old_record?: ProfileRecord;
  record?: ProfileRecord;
};

const jsonHeaders = { "Content-Type": "application/json" };

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function renderApprovedHtml(record: ProfileRecord, appUrl: string) {
  const displayName = escapeHtml(record.display_name || "Analog Archive user");
  const safeUrl = escapeHtml(appUrl);

  return `
    <div style="font-family:Inter,Arial,sans-serif;background:#11100d;color:#f3eadb;padding:24px;">
      <div style="max-width:640px;margin:0 auto;border:1px solid rgba(244,237,226,0.12);background:#18140f;padding:32px;">
        <div style="font-size:11px;letter-spacing:.18em;text-transform:uppercase;color:#a89d8c;margin-bottom:14px;">Analog Archive</div>
        <h1 style="margin:0 0 14px 0;font-size:28px;line-height:1.1;font-family:Georgia,serif;font-weight:700;color:#f3eadb;">Tu acceso fue aprobado</h1>
        <p style="margin:0 0 22px 0;font-size:14px;line-height:1.7;color:#d8ccba;">Hola ${displayName}, tu cuenta ya puede entrar a la beta privada de Analog Archive.</p>
        <a href="${safeUrl}" style="display:inline-block;background:#d94a2a;color:#140f0c;text-decoration:none;padding:14px 18px;font-size:12px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;">Entrar a Analog Archive</a>
      </div>
    </div>
  `;
}

function renderApprovedText(record: ProfileRecord, appUrl: string) {
  return [
    "Tu acceso a Analog Archive fue aprobado",
    "",
    `Hola ${record.display_name || "Analog Archive user"},`,
    "Tu cuenta ya puede entrar a la beta privada.",
    "",
    appUrl,
  ].join("\n");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const webhookSecret = Deno.env.get("PENDING_SIGNUP_WEBHOOK_SECRET");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") || "Analog Archive <onboarding@resend.dev>";
  const publicAppUrl = Deno.env.get("PUBLIC_APP_URL") || "https://dperabeles.github.io/analogdb/analog-db-dashboard.html";

  if (!webhookSecret) {
    return new Response(JSON.stringify({ skipped: true, reason: "missing_webhook_secret" }), {
      status: 202,
      headers: jsonHeaders,
    });
  }

  const requestSecret = req.headers.get("x-webhook-secret");
  if (requestSecret !== webhookSecret) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: jsonHeaders,
    });
  }

  const payload = (await req.json()) as ProfileStatusPayload;
  const record = payload?.record;
  const oldRecord = payload?.old_record;
  if (!record || record.status !== "approved" || oldRecord?.status === "approved") {
    return new Response(JSON.stringify({ skipped: true, reason: "non_approval_payload" }), {
      status: 202,
      headers: jsonHeaders,
    });
  }

  if (!resendApiKey || !record.email) {
    return new Response(JSON.stringify({ skipped: true, reason: "missing_email_configuration" }), {
      status: 202,
      headers: jsonHeaders,
    });
  }

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: fromEmail,
      to: [record.email],
      subject: "Tu acceso a Analog Archive fue aprobado",
      html: renderApprovedHtml(record, publicAppUrl),
      text: renderApprovedText(record, publicAppUrl),
    }),
  });

  const resendBody = await resendResponse.text();
  if (!resendResponse.ok) {
    return new Response(JSON.stringify({
      error: "resend_failed",
      status: resendResponse.status,
      body: resendBody,
    }), {
      status: 502,
      headers: jsonHeaders,
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: jsonHeaders,
  });
});
