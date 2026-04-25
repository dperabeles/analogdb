type PendingProfileRecord = {
  user_id?: string;
  email?: string;
  display_name?: string;
  status?: string;
  created_at?: string;
};

type PendingSignupPayload = {
  type?: string;
  schema?: string;
  table?: string;
  record?: PendingProfileRecord;
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

function renderEmailHtml(record: PendingProfileRecord, appUrl: string) {
  const displayName = escapeHtml(record.display_name || "Sin display name");
  const email = escapeHtml(record.email || "Sin correo");
  const createdAt = escapeHtml(record.created_at || new Date().toISOString());
  const safeUrl = escapeHtml(appUrl);

  return `
    <div style="font-family:Inter,Arial,sans-serif;background:#11100d;color:#f3eadb;padding:24px;">
      <div style="max-width:640px;margin:0 auto;border:1px solid rgba(244,237,226,0.12);background:#18140f;padding:32px;">
        <div style="font-size:11px;letter-spacing:.18em;text-transform:uppercase;color:#a89d8c;margin-bottom:14px;">Analog Archive</div>
        <h1 style="margin:0 0 14px 0;font-size:28px;line-height:1.1;font-family:Georgia,serif;font-weight:700;color:#f3eadb;">Nuevo registro pendiente</h1>
        <p style="margin:0 0 22px 0;font-size:14px;line-height:1.7;color:#d8ccba;">Un usuario nuevo solicitó acceso a la beta privada y está esperando aprobación manual.</p>
        <div style="border:1px solid rgba(244,237,226,0.08);background:#140f0c;padding:18px 20px;margin-bottom:24px;">
          <div style="font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:#8d8375;margin-bottom:10px;">Solicitante</div>
          <div style="font-size:18px;font-weight:700;color:#f3eadb;margin-bottom:6px;">${displayName}</div>
          <div style="font-size:14px;color:#d8ccba;margin-bottom:6px;">${email}</div>
          <div style="font-size:12px;color:#9c9284;">${createdAt}</div>
        </div>
        <a href="${safeUrl}" style="display:inline-block;background:#d94a2a;color:#140f0c;text-decoration:none;padding:14px 18px;font-size:12px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;">Abrir panel Admin</a>
      </div>
    </div>
  `;
}

function renderEmailText(record: PendingProfileRecord, appUrl: string) {
  return [
    "Nuevo registro pendiente en Analog Archive",
    "",
    `Display name: ${record.display_name || "Sin display name"}`,
    `Correo: ${record.email || "Sin correo"}`,
    `Fecha: ${record.created_at || new Date().toISOString()}`,
    "",
    `Admin: ${appUrl}`,
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
  const adminEmail = Deno.env.get("ADMIN_NOTIFICATION_EMAIL");
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

  const payload = (await req.json()) as PendingSignupPayload;
  const record = payload?.record;
  if (!record || record.status !== "pending") {
    return new Response(JSON.stringify({ skipped: true, reason: "non_pending_payload" }), {
      status: 202,
      headers: jsonHeaders,
    });
  }

  if (!resendApiKey || !adminEmail) {
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
      to: [adminEmail],
      subject: "Nuevo registro pendiente en Analog Archive",
      html: renderEmailHtml(record, publicAppUrl),
      text: renderEmailText(record, publicAppUrl),
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
