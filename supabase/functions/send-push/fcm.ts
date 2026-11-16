// Google OAuth and FCM HTTP v1 for send-push (ANA-74). No library: a JWT
// signed with WebCrypto is all FCM needs. Never log the key or the bearer.

export type ServiceAccount = { client_email: string; private_key: string };
type Fetch = typeof fetch;

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Signs the assertion with the service account's PKCS#8 key. */
export async function signAssertion(sa: ServiceAccount, nowSec: number): Promise<string> {
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: nowSec,
    exp: nowSec + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = `${header}.${claims}`;
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signed)));
  return `${signed}.${b64url(sig)}`;
}

/** Exchanges the signed assertion for a short-lived bearer for FCM. */
export async function googleBearer(sa: ServiceAccount, fetchFn: Fetch = fetch): Promise<string> {
  const assertion = await signAssertion(sa, Math.floor(Date.now() / 1000));
  const res = await fetchFn(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`oauth ${res.status}`);
  const json = await res.json();
  const bearer = json.access_token; // secret-scan: allow (OAuth field name, not a value)
  if (typeof bearer !== "string" || bearer === "") throw new Error("oauth: empty");
  return bearer;
}

export function fcmPayload(token: string, msg: { title: string; body: string }, kind: string) {
  return {
    message: {
      token,
      notification: { title: msg.title, body: msg.body },
      data: { kind },
      apns: { payload: { aps: { sound: "default" } } },
      android: { priority: "HIGH" },
    },
  };
}

export async function sendFcm(
  bearer: string,
  projectId: string,
  token: string,
  msg: { title: string; body: string },
  kind: string,
  fetchFn: Fetch = fetch,
): Promise<{ status: number; body: unknown }> {
  const res = await fetchFn(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${bearer}` },
    body: JSON.stringify(fcmPayload(token, msg, kind)),
  });
  let body: unknown = null;
  try {
    body = await res.json();
  } catch {
    body = null;
  }
  return { status: res.status, body };
}

/** Constant-time comparison for the shared secret. */
export function safeEqual(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
