"use server";

import type { ContactState } from "./contact-types";

const TOPICS = new Set(["privacy", "data-export", "delete", "legal", "general"]);
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

/// Procesa el formulario de contacto requerido por compliance (ANA-28).
///
/// Envía el mensaje vía Resend (REST, sin SDK) a `CONTACT_TO_EMAIL`. Si el
/// proveedor de correo no está configurado (`RESEND_API_KEY` / `CONTACT_FROM_EMAIL`),
/// degrada con elegancia pidiendo escribir directo a legal@analog-archive.com.
export async function submitContact(
  _prev: ContactState,
  formData: FormData,
): Promise<ContactState> {
  // Honeypot: bots rellenan campos ocultos. Fingimos éxito y descartamos.
  if (String(formData.get("company") ?? "").trim()) {
    return { ok: true, message: "Gracias, hemos recibido tu mensaje." };
  }

  const name = String(formData.get("name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const topic = String(formData.get("topic") ?? "general").trim();
  const message = String(formData.get("message") ?? "").trim();

  if (!EMAIL_RE.test(email)) {
    return { ok: false, message: "Ingresa un correo válido para poder responderte." };
  }
  if (!TOPICS.has(topic)) {
    return { ok: false, message: "Selecciona un tema válido." };
  }
  if (message.length < 10) {
    return { ok: false, message: "Cuéntanos un poco más (mínimo 10 caracteres)." };
  }

  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.CONTACT_FROM_EMAIL;
  const to = process.env.CONTACT_TO_EMAIL ?? "legal@analog-archive.com";

  if (!apiKey || !from) {
    return {
      ok: false,
      message:
        "El formulario aún no está conectado. Escríbenos directamente a legal@analog-archive.com.",
    };
  }

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [to],
        reply_to: email,
        subject: `[Contacto · ${topic}] ${name || email}`,
        text: [
          `Tema: ${topic}`,
          `Nombre: ${name || "—"}`,
          `Correo: ${email}`,
          "",
          message,
        ].join("\n"),
      }),
    });

    if (!res.ok) {
      return {
        ok: false,
        message:
          "No pudimos enviar tu mensaje. Intenta de nuevo o escríbenos a legal@analog-archive.com.",
      };
    }

    return {
      ok: true,
      message: "Gracias. Hemos recibido tu mensaje y te responderemos pronto.",
    };
  } catch {
    return {
      ok: false,
      message:
        "No pudimos enviar tu mensaje. Intenta de nuevo o escríbenos a legal@analog-archive.com.",
    };
  }
}
