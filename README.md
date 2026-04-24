# Analog Archive Database

Single-file dashboard for tracking, developing, and archiving analog film rolls.

The current product is a self-contained `analog-db-dashboard.html` file backed by Supabase. It opens directly in the browser and includes dashboard views, roll editing, statistics, a timeline, and a camera catalog.

---

## What It Is

Analog Archive is a personal archive system for film photographers. It is designed to track a roll from the moment it is loaded into a camera through development and into the archive, while keeping the interface editorial, darkroom-inspired, and lightweight.

This version is intentionally simple from an engineering standpoint:

- one HTML file
- vanilla CSS and JavaScript
- Supabase as the backend
- no build step
- no framework

---

## Current Features

### Dashboard
- Editorial dashboard with archive counts and recent activity
- Format breakdown cards
- Workflow sections for rolls in progress
- Top film stock ranking

### Roll Database
- Sortable table of rolls
- Filters for film type, format, freshness, camera, and lab
- Search across roll ID, film, camera, location, tags, and notes
- Detail modal for each roll

### Roll Editor
- Create and edit rolls in a darkroom-themed modal
- Smart selects for film stock, manufacturer, camera maker, model, labs, and lens
- Auto-fill for ISO, film type, and manufacturer based on stock
- Multi-select categories and hashtag-style tags
- Rating, push/pull, notes, and timeline metadata

### Supported Film Formats
- `35`
- `120`
- `Super8`
- `110`
- `16mm`
- `Large Format`

### Stats and Timeline
- Statistics by stock, lab, camera, location, categories, tags, and format
- Timeline view grouped chronologically
- Dashboard and stats views reflect the current format set

### Cameras
- Camera catalog with maker, model, format, and type
- Add and delete camera entries
- Usage summaries and charts

### Data and Sync
- Supabase-backed data storage
- LocalStorage fallback for offline resilience
- JSON export

---

## Stack

| Layer | Technology |
|---|---|
| Frontend | HTML + CSS + Vanilla JavaScript |
| Backend | [Supabase](https://supabase.com) |
| UI Fonts | DM Mono, Playfair Display, Fraunces, Inter, Special Elite |
| Runtime | Browser, no build step |

---

## Design Direction

- Darkroom palette with warm browns and safelight red accents
- Editorial structure rather than app-dashboard chrome
- Monospace technical UI mixed with serif display typography
- Film grain and filmstrip-inspired details

---

## Roadmap

Short-term roadmap:

1. Proper auth
2. Web app migration to next.js
3. Closed beta
4. Mobile app (ios only for short time)
5. Switching betweem Easy and Advanced mode for new entries

Longer-term roadmap:

- Full gallery for each film roll taken, with tagging system working in every photo.
- Full scale analitics
- Full sync between all platforms
- System for adding film stock each user has
- User added examples for each film stock and its different settings

---

## Project Status

Active development.
