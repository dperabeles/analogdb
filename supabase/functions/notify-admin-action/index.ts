// Aviso por correo cuando se propone o se ejecuta un cambio de rol de admin.
//
// La llama la BASE DE DATOS vía pg_net (trigger `admin_actions_notify`), no un
// usuario con sesión. Por eso necesita `verify_jwt = false` en config.toml —
// sin eso la puerta de entrada responde 401 UNAUTHORIZED_NO_AUTH_HEADER antes
// de que este código corra. La autenticación real es el header
// `x-webhook-secret`.
//
// Comparte secreto con notify-pending-signup (PENDING_SIGNUP_WEBHOOK_SECRET)
// a propósito: es el mismo emisor (nuestra propia base) y un secreto menos
// que rotar.
//
// El valor de seguridad de este aviso: si te llega un correo de una propuesta
// que tú no hiciste, alguien tiene tu sesión de admin.

type AdminActionRecord = {
  id?: string;
  action_type?: string;
  status?: string;
  request_reason?: string | null;
  resolved_reason?: string | null;
  created_at?: string;
  expires_at?: string | null;
};

type Party = {
  email?: string | null;
  display_name?: string | null;
};

type AdminActionPayload = {
  event?: "requested" | "executed";
  record?: AdminActionRecord;
  target?: Party;
  actor?: Party;
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

function describeParty(party: Party | undefined) {
  const name = party?.display_name?.trim() || "Sin display name";
  const email = party?.email?.trim() || "Sin correo";
  return `${name} (${email})`;
}

function describeAction(actionType: string | undefined) {
  if (actionType === "promote_to_admin") return "Dar admin";
  if (actionType === "demote_from_admin") return "Quitar admin";
  return actionType || "Cambio de rol";
}

function subjectFor(event: string, actionType: string | undefined) {
  const action = describeAction(actionType).toLowerCase();
  return event === "executed"
    ? `Se ejecutó un cambio de rol: ${action}`
    : `Se propuso un cambio de rol: ${action}`;
}

function renderEmailHtml(payload: AdminActionPayload, appUrl: string) {
  const event = payload.event === "executed" ? "executed" : "requested";
  const record = payload.record ?? {};
  const heading = event === "executed"
    ? "Cambio de rol ejecutado"
    : "Cambio de rol propuesto";
  const lead = event === "executed"
    ? "El cambio ya surtió efecto. Si no lo reconoces, revoca el acceso y cambia tu contraseña ahora mismo."
    : "Alguien propuso un cambio de rol de administrador. Si no fuiste tú, alguien tiene una sesión de admin que no debería.";

  const rows: Array<[string, string]> = [
    ["Acción", describeAction(record.action_type)],
    ["Sobre", describeParty(payload.target)],
    ["Propuesta por", describeParty(payload.actor)],
  ];
  if (record.request_reason) rows.push(["Motivo", record.request_reason]);
  if (event === "executed" && record.resolved_reason) {
    rows.push(["Resolución", record.resolved_reason]);
  }
  if (event === "requested" && record.expires_at) {
    rows.push(["Caduca", record.expires_at]);
  }

  const rowsHtml = rows
    .map(([label, value]) => `
          <div style="margin-bottom:10px;">
            <div style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:#8d8375;margin-bottom:3px;">${escapeHtml(label)}</div>
            <div style="font-size:15px;color:#f3eadb;">${escapeHtml(value)}</div>
          </div>`)
    .join("");

  return `
    <div style="font-family:Inter,Arial,sans-serif;background:#11100d;color:#f3eadb;padding:24px;">
      <div style="max-width:640px;margin:0 auto;border:1px solid rgba(244,237,226,0.12);background:#18140f;padding:32px;">
        <div style="font-size:11px;letter-spacing:.18em;text-transform:uppercase;color:#a89d8c;margin-bottom:14px;">Analog Archive</div>
        <h1 style="margin:0 0 14px 0;font-size:28px;line-height:1.1;font-family:Georgia,serif;font-weight:700;color:#f3eadb;">${escapeHtml(heading)}</h1>
        <p style="margin:0 0 22px 0;font-size:14px;line-height:1.7;color:#d8ccba;">${escapeHtml(lead)}</p>
        <div style="border:1px solid rgba(244,237,226,0.08);background:#140f0c;padding:18px 20px;margin-bottom:24px;">${rowsHtml}
        </div>
        <a href="${escapeHtml(appUrl)}" style="display:inline-block;background:#d94a2a;color:#140f0c;text-decoration:none;padding:14px 18px;font-size:12px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;">Abrir panel Admin</a>
      </div>
    </div>
  `;
}

function renderEmailText(payload: AdminActionPayload, appUrl: string) {
  const event = payload.event === "executed" ? "executed" : "requested";
  const record = payload.record ?? {};
  const lines = [
    event === "executed" ? "Cambio de rol ejecutado" : "Cambio de rol propuesto",
    "",
    `Acción: ${describeAction(record.action_type)}`,
    `Sobre: ${describeParty(payload.target)}`,
    `Propuesta por: ${describeParty(payload.actor)}`,
  ];
  if (record.request_reason) lines.push(`Motivo: ${record.request_reason}`);
  if (event === "executed" && record.resolved_reason) {
    lines.push(`Resolución: ${record.resolved_reason}`);
  }
  if (event === "requested" && record.expires_at) {
    lines.push(`Caduca: ${record.expires_at}`);
  }
  lines.push("", `Admin: ${appUrl}`);
  return lines.join("\n");
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

  const payload = (await req.json()) as AdminActionPayload;
  if (!payload?.record || !payload?.event) {
    return new Response(JSON.stringify({ skipped: true, reason: "empty_payload" }), {
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
      subject: subjectFor(payload.event, payload.record.action_type),
      html: renderEmailHtml(payload, publicAppUrl),
      text: renderEmailText(payload, publicAppUrl),
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
