"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase/client";

export function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function handleSignOut() {
    setBusy(true);
    const supabase = createBrowserSupabaseClient();
    await supabase.auth.signOut({ scope: "local" });
    router.refresh();
  }

  return (
    <button className="secondary-action" type="button" onClick={handleSignOut} disabled={busy}>
      {busy ? "Cerrando sesión..." : "Cerrar sesión"}
    </button>
  );
}
