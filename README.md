# Analog Archive Database

A personal analog film roll tracker and archive dashboard. Built as a single-file web app backed by Supabase.

![Dark dashboard with film grain, sidebar navigation, KPI cards and roll table]

---

## Overview

Analog Archive is a personal tool for photographers who shoot on film. It tracks every roll from the moment it's loaded into a camera through development and into the archive — with stats, timelines, and a full inventory of cameras and film stocks.

The current version is a single HTML file (`analog-db-dashboard.html`) that runs directly in the browser with no build step. The roadmap includes a migration to Next.js with a companion Expo mobile app for field use.

---

## Features

### Dashboard
- **KPI cards** — total rolls shot, rolls in progress (in camera / to develop / in development), format breakdown (35mm / 120 / Super 8)
- **Activity chart** — rolls loaded over time, switchable between monthly, quarterly, and yearly views
- **Workflow kanban** — rolls grouped by status in a compact column view
- **Film stock ranking** — top stocks by rolls shot, with mini usage bars

### Roll Database
- Full sortable table of all rolls
- Filter by status, format, and film stock
- Live search across roll ID, film, camera, and location
- Click any row to open the roll detail view

### Roll Editor — Simple & Advanced modes

New rolls can be created in two modes, accessible from the same "+" button:

**Simple mode** — designed for beginners and field use
- 3 fields only: film stock, camera, format
- One tap to load — done in under 5 seconds
- No prior knowledge of ISO, push/pull, or lab workflows required
- Saves with the same data structure; missing fields can be filled in later

**Advanced mode** — full control for experienced users
- **Smart camera selector** — autocomplete filtered by maker and format; auto-fills maker and format when a model is selected
- **Smart film stock selector** — autocomplete filtered by manufacturer; auto-fills ISO and type when a stock is selected
- **Locations dropdown** — top 3 most-used locations shown first, then alphabetical, with an inline "add new" option at the bottom
- **Star rating** (1–5) for the roll
- **Push/pull** tracking
- Date fields for each stage: loaded, shot, sent to lab, developed, scanned
- Notes field
- Delete with confirmation

Both modes write to the same roll record. A roll created in Simple mode can always be expanded later using Advanced mode via the edit button in the detail view.

### Roll Detail View
- Full read-only summary of a roll's data
- Inline status change buttons to advance the roll through the workflow

### Status Workflow
```
In Camera → To Develop → In Development → Developed
```
Each transition is tracked with a date and reflected immediately in the dashboard.

### Stats Page
- Usage breakdown by film stock, camera, format, and location
- Bar charts ranked by roll count

### Timeline
- Chronological view of all rolls grouped by month
- Each roll shown as a card with status, film, camera, and format

### Cameras
- Full inventory of cameras with maker, model, format, and type
- Add and delete cameras
- Usage charts by format and type

### Data
- **Supabase backend** — all rolls, cameras, and film stocks are stored and synced remotely
- **Export** — download all rolls as JSON
- Sync status toast on every save/update

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Vanilla HTML + CSS + JavaScript |
| Database | [Supabase](https://supabase.com) (PostgreSQL) |
| Fonts | DM Mono, Playfair Display, Fraunces, Inter |
| Hosting | Open directly in browser (no build step) |

No frameworks, no bundlers, no dependencies beyond the Supabase JS client loaded via CDN.

---

## Design

- **Darkroom theme** — deep brown-blacks (`#1e1a15`) with safelight red (`#d94a2a`) as the accent
- **Film grain overlay** — subtle SVG noise layer over the entire UI
- **Filmstrip perforations** on the active nav item
- Status pills with color-coded states and a pulsing animation for rolls currently in camera
- Format badges: terracotta for 35mm, steel blue for 120, ochre for Super 8

---

## Roadmap

The project is being migrated to a full web application.

**Planned stack:**
- **Web app** — Next.js + Supabase (same database)
- **Mobile app** — Expo (iOS field companion for quick roll logging)

The mobile app is scoped to field use only: create roll, change status, check inventory. No light meter — dedicated apps already handle that better.

The **Simple/Advanced roll creation modes** are especially relevant for mobile — the Simple mode becomes the primary screen in the field, with Advanced available for users who want to fill in all the metadata.

---

## Project Status

> Active development — prototype phase.  
> Single-file version is fully functional with real data.  
