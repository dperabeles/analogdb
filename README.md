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

## Repo Notes

- Main app file: [`analog-db-dashboard.html`](./analog-db-dashboard.html)
- Bootstrap schema: [`supabase/schema.sql`](./supabase/schema.sql)
- Incremental remote alignment: [`supabase/migrations/20260424_release_alignment.sql`](./supabase/migrations/20260424_release_alignment.sql)

## Near-term Roadmap

1. Public release hardening before deployment
2. Expand admin tools for approvals and role governance
3. Add more shared/global metrics where privacy allows
4. Add `En Casa` to reveal and scan flows
5. Plan migration path to Next.js after beta validation

## Longer-term Roadmap

- Full photo gallery per roll with frame tagging
- Richer anonymous global analytics
- User-submitted stock examples and shooting references
- Country-aware lab presets and better lab analytics
- Cross-platform product expansion after beta

## Status

Active development.
