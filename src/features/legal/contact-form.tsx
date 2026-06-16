"use client";

import { useActionState } from "react";

import { submitContact } from "./contact-actions";
import { initialContactState } from "./contact-types";

export function ContactForm() {
  const [state, action, pending] = useActionState(
    submitContact,
    initialContactState,
  );

  return (
    <form action={action} className="legal-form">
      {/* Honeypot anti-spam (oculto a usuarios reales). */}
      <input
        type="text"
        name="company"
        tabIndex={-1}
        autoComplete="off"
        aria-hidden="true"
        className="legal-hp"
      />

      <label className="legal-field">
        <span>Tema</span>
        <select name="topic" defaultValue="general">
          <option value="privacy">Privacidad / mis datos</option>
          <option value="data-export">Exportar mis datos</option>
          <option value="delete">Eliminar mi cuenta</option>
          <option value="legal">Asunto legal</option>
          <option value="general">General</option>
        </select>
      </label>

      <label className="legal-field">
        <span>
          Nombre <em>(opcional)</em>
        </span>
        <input type="text" name="name" autoComplete="name" />
      </label>

      <label className="legal-field">
        <span>Correo</span>
        <input
          type="email"
          name="email"
          required
          autoComplete="email"
          placeholder="tu@correo.com"
        />
      </label>

      <label className="legal-field">
        <span>Mensaje</span>
        <textarea
          name="message"
          required
          rows={6}
          placeholder="¿En qué podemos ayudarte?"
        />
      </label>

      {state.message && (
        <p className={`legal-form-msg ${state.ok ? "is-ok" : "is-err"}`} role="status">
          {state.message}
        </p>
      )}

      <button type="submit" className="legal-submit" disabled={pending}>
        {pending ? "Enviando…" : "Enviar mensaje"}
      </button>
    </form>
  );
}
