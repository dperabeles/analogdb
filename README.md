# Analog Archive

Private beta web app for tracking analog film rolls from camera to archive.

The current product is still centered on a single-file frontend, [`analog-db-dashboard.html`](./analog-db-dashboard.html), backed by Supabase and intended to ship as a lightweight browser-based experience.

## Current State

- Private beta access with email/password auth
- Manual approval flow for new users
- Founder/admin access inside the app
- Per-user private rolls and cameras
- Shared global catalogs for film stocks and labs
- Public landing page with global archive metrics
- Darkroom-inspired editorial UI

## Main Features

### Archive

- Dashboard with archive counts, workflow sections, and recent activity
- Sortable roll database with filters and search
- Roll editor with smart selects, tags, categories, rating, push/pull, and notes
- Timeline and statistics views
- Camera catalog with usage summaries
- JSON export/import tools

### Multi-user Beta

- Users sign up from the landing page
- New accounts stay pending until approved by an admin
- Each user sees only their own rolls, stats, and private cameras
- Shared metrics remain global where intended, such as landing metrics and film stock popularity

### Supported Formats

- `35`
- `120`
- `Super8`
- `110`
- `16mm`
- `Large Format`

## Stack

| Layer | Technology |
|---|---|
| Frontend | HTML + CSS + Vanilla JavaScript |
| Backend | [Supabase](https://supabase.com) |
| Auth | Supabase Auth |
| Database | PostgreSQL + RLS |
| Runtime | Browser, no build step |

## Design Direction

- Warm darkroom palette with safelight red accents
- Editorial composition instead of generic dashboard chrome
- Serif display typography mixed with technical monospace UI
- Lightweight, direct browser delivery

## Longer-term Roadmap

- Full photo gallery per roll with frame tagging
- Richer anonymous global analytics
- User-submitted stock examples and shooting references
- Country-aware lab presets and better lab analytics
- Cross-platform product expansion after beta

## Operación

### Dependencias fijas

`package.json` fija versiones exactas, y `package-lock.json` coincide con ellas (lo comprueba `tests/dependencies-pinned.test.js`). Vercel instala lo que dice el lockfile. Para actualizar algo, hazlo a propósito: `npm install paquete@X.Y.Z --save-exact`, corre las pruebas y el build, y commitea los dos archivos.

### Después de cada migración

1. Ensaya la migración con rollback en staging y en producción, como siempre.
2. Ya aplicada, corre `supabase/tests/smoke_after_migration.sql`, primero en staging y luego en producción. Como usuario normal crea, edita y borra un rollo por escritura directa, lee `rolls_flat` por su `#` y comprueba que otra cuenta no lo ve. Termina en RAISE: el resultado esperado es `RESULTADO: OK` y no deja nada escrito.
3. Prueba la web y la app contra staging antes de tocar producción (ver abajo).

Así se detecta lo que rompió producción el 11-nov-2026: los ensayos solo usaban RPC `security definer`, y crear un rollo por insert directo fallaba (ANA-191).

### Web de staging (por configurar en Vercel)

Hoy analog-archive.com solo habla con producción. Para probar la web contra staging:

1. En Vercel → Project → Settings → Environments, crea un entorno personalizado `staging`, ligado a una rama `staging`; o usa los Preview deployments de la rama.
2. Define ahí `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_ANON_KEY` del proyecto de staging (`wxwfcxlyqnczujuoqnlj`). No pongas `RESEND_API_KEY`, para que staging no mande correos.
3. En Supabase de staging → Authentication → URL Configuration, agrega la URL de ese despliegue a las Redirect URLs.

## Status

Active development.

## License

This project is proprietary software. All rights reserved.
See [LICENSE](./LICENSE).
