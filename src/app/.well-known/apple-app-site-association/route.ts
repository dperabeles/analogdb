import aasa from "./aasa.json";

// Enlaces universales de iOS (ANA-69). Apple descarga este archivo desde su
// CDN al instalar la app y decide qué rutas de analog-archive.com la abren:
// solo /app/*. Los correos de acceso siguen abriendo la web.
export const dynamic = "force-static";

export function GET() {
  return new Response(JSON.stringify(aasa), {
    headers: { "Content-Type": "application/json" },
  });
}
