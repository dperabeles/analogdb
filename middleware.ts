import { type NextRequest, NextResponse } from "next/server";
import { applyGpc } from "@/lib/privacy/gpc";
import { updateSupabaseSession } from "@/lib/supabase/middleware";
import { isPausedWebappPath } from "@/lib/webapp-paused";

export async function middleware(request: NextRequest) {
  // The web app is paused: its pages go to the home page, in the same
  // language. Temporary (307), so nothing caches it for when it returns.
  if (isPausedWebappPath(request.nextUrl.pathname)) {
    const home = new URL("/", request.url);
    const lang = request.nextUrl.searchParams.get("lang");
    if (lang) home.searchParams.set("lang", lang);
    return applyGpc(request, NextResponse.redirect(home, 307));
  }
  const response = await updateSupabaseSession(request);
  // Global Privacy Control (ANA-31). Va después de la sesión porque
  // `updateSupabaseSession` puede reconstruir la respuesta al refrescar
  // cookies de auth — escribir antes se perdería.
  return applyGpc(request, response);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|\\.well-known|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"
  ]
};
