/** @type {import('next').NextConfig} */
const nextConfig = {
  // Las páginas legales leen su markdown desde src/content/legal/*.md vía fs.
  // Aunque se prerenderizan estáticamente, incluimos los .md en el trace de
  // salida para que Vercel los empaquete si alguna ruta se evalúa en runtime.
  outputFileTracingIncludes: {
    "/privacy": ["./src/content/legal/**"],
    "/terms": ["./src/content/legal/**"],
    "/cookies": ["./src/content/legal/**"],
  },
};

module.exports = nextConfig;
