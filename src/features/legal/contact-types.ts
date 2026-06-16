/// Estado del formulario de contacto, compartido entre el server action y el
/// formulario cliente. Vive aparte de `contact-actions.ts` porque ese módulo es
/// `"use server"` y solo puede exportar funciones async.
export interface ContactState {
  ok: boolean;
  message: string;
}

export const initialContactState: ContactState = { ok: false, message: "" };
