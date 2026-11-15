import { redirect } from "next/navigation";

/// Without a session, the old webapp pages send the reader to the home
/// page's sign-in. Accounts are created in the app (DEC-013), so the web
/// no longer carries a sign-up form of its own.
export function AccessGate(): never {
  redirect("/#acceso");
}
