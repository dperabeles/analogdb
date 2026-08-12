import type { NextRequest } from "next/server";
import { applyGpc } from "@/lib/privacy/gpc";
import { updateSupabaseSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  const response = await updateSupabaseSession(request);
  // Global Privacy Control (ANA-31). Va después de la sesión porque
  // `updateSupabaseSession` puede reconstruir la respuesta al refrescar
  // cookies de auth — escribir antes se perdería.
  return applyGpc(request, response);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"
  ]
};
