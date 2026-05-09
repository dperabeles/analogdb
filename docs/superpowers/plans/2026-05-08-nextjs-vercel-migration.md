# Next.js Vercel Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Analog Archive from GitHub Pages to a parallel Vercel deployment, then migrate the product to Next.js without interrupting the closed beta.

**Architecture:** Keep `main` as the stable GitHub Pages beta while `feature/nextjs-vercel-migration` carries Vercel and Next.js work. Both frontends use the same Supabase project, so beta tester data remains shared and no export/import flow is required. Supabase schema, RLS, and auth redirects must remain backward-compatible until GitHub Pages is retired.

**Tech Stack:** Static HTML/CSS/Vanilla JS baseline, Vercel static hosting, future Next.js App Router, Supabase Auth/Postgres/Storage, later React Native consuming the same backend contracts.

---

## Current Migration Status

- Branch: `feature/nextjs-vercel-migration`
- Remote branch: `origin/feature/nextjs-vercel-migration`
- Vercel project: `analogdb-repo`
- Live Vercel URL: `https://analogdb-repo.vercel.app`
- Custom domains: `https://analog-archive.com`, `https://www.analog-archive.com`
- Deployment id: `dpl_5BZJnFo66sadYJ63q5bF1F52wEat`
- Deployment status: Ready
- Validated routes: `/`, `/analog-db-dashboard.html`, `/forgot-password.html`, `/reset-password.html`
- Supabase Auth redirects: Vercel and custom-domain URLs added and pushed to remote.

---

## File Structure

- `.vercelignore`: Prevents private docs, local graph output, local Supabase state, and tests from being uploaded to Vercel.
- `vercel.json`: Preserves existing `.html` routes and adds baseline browser security headers for the static Vercel preview.
- `docs/superpowers/plans/2026-05-08-nextjs-vercel-migration.md`: Tracks the migration program.
- Future `package.json`: Introduces the Next.js app only after the static Vercel preview is validated.
- Future `src/app/`: Next.js App Router pages and layouts.
- Future `src/lib/supabase/`: Browser/server Supabase client factories and typed query helpers.
- Future `src/features/rolls/`: Roll list, editor, filters, and data transforms.
- Future `src/features/auth/`: Login, signup, pending/rejected states, password recovery, and session handling.
- Future `src/features/admin/`: Admin approval/reactivation flows.
- Future `src/shared/`: UI primitives and shared domain types that React Native can mirror later.

---

### Task 1: Static Vercel Preview

**Files:**
- Create: `.vercelignore`
- Create: `vercel.json`
- Verify: `index.html`
- Verify: `analog-db-dashboard.html`
- Verify: `forgot-password.html`
- Verify: `reset-password.html`

- [x] **Step 1: Confirm private/local files are ignored by Vercel**

Run:

```bash
git check-ignore -v HANDOFF.md DESIGN-SYSTEM.md ROADMAP.md graphify-out/graph.json supabase/.temp/project-ref
grep -E '^(HANDOFF|DESIGN-SYSTEM|ROADMAP|graphify-out/|supabase/\\.temp/|supabase/\\*.sql)' .vercelignore
```

Expected: private docs and local build/runtime artifacts are excluded by `.gitignore` locally and by `.vercelignore` during Vercel upload.

- [x] **Step 2: Deploy the static branch to Vercel**

Run through the Vercel integration or CLI from the repo root:

```bash
vercel deploy
```

Expected: Vercel creates a preview URL for `feature/nextjs-vercel-migration`.

- [x] **Step 3: Validate the Vercel preview manually**

Open these routes on the Vercel URL:

```text
/
/analog-db-dashboard.html
/forgot-password.html
/reset-password.html
```

Expected:
- `/` redirects to `./analog-db-dashboard.html`.
- Dashboard renders the login/beta gate.
- Forgot password page renders.
- Reset password page renders.
- Browser console has no fatal asset or module errors.

- [x] **Step 4: Add Supabase auth redirect URLs**

Add the Vercel preview URL in Supabase Auth settings:

```text
https://<vercel-preview-host>/reset-password.html
https://<vercel-preview-host>/forgot-password.html
https://<vercel-preview-host>/analog-db-dashboard.html
```

Expected: password recovery links can return to the Vercel preview without being blocked by Supabase redirect allow-list rules.

Also add the custom production domains:

```text
https://analog-archive.com/analog-db-dashboard.html
https://analog-archive.com/forgot-password.html
https://analog-archive.com/reset-password.html
https://www.analog-archive.com/analog-db-dashboard.html
https://www.analog-archive.com/forgot-password.html
https://www.analog-archive.com/reset-password.html
```

- [x] **Step 5: Commit static Vercel baseline**

Run:

```bash
git add .vercelignore vercel.json docs/superpowers/plans/2026-05-08-nextjs-vercel-migration.md
git commit -m "chore: prepare vercel migration branch"
```

Expected: commit contains only Vercel config and this migration plan.

---

### Task 2: Next.js Shell

**Files:**
- Create: `package.json`
- Create: `next.config.js`
- Create: `tsconfig.json`
- Create: `src/app/layout.tsx`
- Create: `src/app/page.tsx`
- Create: `src/app/globals.css`
- Create: `src/app/dashboard/page.tsx`

- [ ] **Step 1: Add the Next.js project skeleton**

Create `package.json`:

```json
{
  "name": "analog-archive",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@supabase/ssr": "latest",
    "@supabase/supabase-js": "latest",
    "next": "latest",
    "react": "latest",
    "react-dom": "latest"
  },
  "devDependencies": {
    "@types/node": "latest",
    "@types/react": "latest",
    "@types/react-dom": "latest",
    "typescript": "latest"
  }
}
```

Expected: dependencies match a standard Next.js App Router web app.

- [ ] **Step 2: Add a minimal App Router shell**

Create `src/app/page.tsx`:

```tsx
import Link from "next/link";

export default function HomePage() {
  return (
    <main>
      <h1>Analog Archive</h1>
      <Link href="/dashboard">Open archive</Link>
    </main>
  );
}
```

Expected: Vercel can build a minimal Next.js version before feature migration begins.

- [ ] **Step 3: Validate build**

Run:

```bash
npm install
npm run build
```

Expected: `next build` completes without TypeScript or route errors.

- [ ] **Step 4: Commit shell**

Run:

```bash
git add package.json package-lock.json next.config.js tsconfig.json src/app
git commit -m "chore: scaffold nextjs app"
```

Expected: commit introduces only the framework shell, not product behavior.

---

### Task 3: Shared Supabase Contracts

**Files:**
- Create: `src/lib/supabase/client.ts`
- Create: `src/lib/supabase/server.ts`
- Create: `src/lib/env.ts`
- Create: `src/types/database.ts`

- [ ] **Step 1: Move public Supabase config to env variables**

Create `src/lib/env.ts`:

```ts
export const publicEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? ""
};

export function assertPublicEnv() {
  if (!publicEnv.supabaseUrl || !publicEnv.supabaseAnonKey) {
    throw new Error("Missing Supabase public environment variables");
  }
}
```

Expected: Next.js no longer hardcodes Supabase config inside page code.

- [ ] **Step 2: Add Vercel environment variables**

Set these in Vercel for preview and production:

```text
NEXT_PUBLIC_SUPABASE_URL=https://dqjjxxqruxxfsfoejdzl.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<current publishable anon key>
```

Expected: preview and production deployments use the same Supabase project as GitHub Pages.

- [ ] **Step 3: Commit Supabase foundation**

Run:

```bash
git add src/lib/supabase src/lib/env.ts src/types/database.ts
git commit -m "chore: add supabase client foundation"
```

Expected: commit only adds shared backend access infrastructure.

---

### Task 4: Feature Parity Migration

**Files:**
- Create: `src/features/auth/`
- Create: `src/features/rolls/`
- Create: `src/features/admin/`
- Modify: `src/app/dashboard/page.tsx`

- [ ] **Step 1: Migrate auth gates**

Implement login, signup pending state, rejected state, logout, and password recovery routes before moving roll data screens.

Expected: a beta tester can authenticate in Next.js and reach an empty dashboard shell.

- [ ] **Step 2: Migrate roll read flows**

Implement roll list, filters, sort, and detail view using backward-compatible queries against existing Supabase tables.

Expected: data created from GitHub Pages appears in the Next.js preview.

- [ ] **Step 3: Migrate roll write flows**

Implement create/edit roll with the same fields currently supported by `analog-db-dashboard.html`.

Expected: records created in Next.js remain visible and editable in GitHub Pages.

- [ ] **Step 4: Migrate admin flows**

Implement pending/rejected/approved profile management after regular user flows are stable.

Expected: founder/admin workflows remain available before GitHub Pages is retired.

- [ ] **Step 5: Commit each migrated feature separately**

Use commit messages like:

```bash
git commit -m "feat: migrate auth gates to nextjs"
git commit -m "feat: migrate roll list to nextjs"
git commit -m "feat: migrate roll editor to nextjs"
git commit -m "feat: migrate admin approvals to nextjs"
```

Expected: each commit can be reviewed and rolled back independently.

---

### Task 5: Cutover Readiness

**Files:**
- Modify: `README.md`
- Modify: Vercel project settings
- Modify: Supabase Auth URL settings

- [ ] **Step 1: Run parity checklist**

Validate:

```text
login/logout
signup pending state
password recovery
roll list
roll create/edit
camera flows
stats/timeline views
admin approval/rejection/reactivation
mobile layout
```

Expected: Vercel/Next.js is at parity or better than GitHub Pages.

- [ ] **Step 2: Move beta testers gradually**

Invite 1-2 trusted testers to the Vercel preview first, then expand.

Expected: real Supabase data works in both frontends during overlap.

- [x] **Step 3: Assign product domains**

Current mapping:

```text
analog-archive.com -> Vercel static migration baseline
www.analog-archive.com -> Vercel static migration baseline
app.analog-archive.com -> Vercel app
beta-next.analog-archive.com -> temporary migration preview
```

Expected: DNS is aligned now. Supabase redirects are still tracked under Task 1 Step 4 before tester use.

- [ ] **Step 4: Retire GitHub Pages only after verified parity**

Keep `main` stable until Vercel is the accepted production target.

Expected: no beta tester needs to export/import catalog data.

---

## Self-Review

- Spec coverage: deploy-in-parallel, shared Supabase data, Next.js migration, later React Native readiness, and no GitHub Pages interruption are all covered.
- Placeholder scan: no `TBD` or open-ended task placeholders remain.
- Type consistency: future TypeScript paths and environment variable names are consistent across tasks.

---

## Progress Log

### 2026-05-09: Static Vercel Baseline And Custom Domain

Completed:

- Created branch `feature/nextjs-vercel-migration` without using a temporary worktree.
- Added `.vercelignore` so Vercel does not upload local/private docs or local tool artifacts.
- Added `vercel.json` with static hosting defaults and baseline security headers.
- Created Vercel project `analogdb-repo`.
- Deployed current static app to `https://analogdb-repo.vercel.app`.
- Pushed branch `feature/nextjs-vercel-migration` to `origin`.
- Added custom domains to Vercel:
  - `analog-archive.com`
  - `www.analog-archive.com`
- Configured Cloudflare DNS through the user:
  - `A @ 76.76.21.21`
  - `A www 76.76.21.21`
- Assigned aliases explicitly:
  - `analog-archive.com -> analogdb-repo-e5874zgsu-arqdiegoperabeles-2865s-projects.vercel.app`
  - `www.analog-archive.com -> analogdb-repo-e5874zgsu-arqdiegoperabeles-2865s-projects.vercel.app`
- Validated HTTPS `200` responses for:
  - `https://analog-archive.com/`
  - `https://www.analog-archive.com/`
  - `https://analog-archive.com/analog-db-dashboard.html`
  - `https://www.analog-archive.com/analog-db-dashboard.html`
- Confirmed the deployed dashboard still points to the existing Supabase project `dqjjxxqruxxfsfoejdzl`.

Validation commands used:

```bash
node --check auth-recovery.js
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js
python3 -m unittest tests/test_exposure_settings.py tests/test_film_catalog.py tests/test_rejected_admin_ui.py
curl -sS -I https://analog-archive.com/analog-db-dashboard.html
curl -sS -I https://www.analog-archive.com/analog-db-dashboard.html
curl -sS https://analog-archive.com/analog-db-dashboard.html | rg -n "Analog Archive|SUPABASE_URL|gateForgotPasswordLink"
```

Errors / lessons:

- `git switch -c feature/nextjs-vercel-migration` failed inside the sandbox with `Operation not permitted` when creating the ref lock. Use approved/escalated git commands for branch creation in this workspace when the sandbox blocks `.git` writes.
- Vercel MCP could not deploy directly and instructed using `vercel deploy`; use `npx --yes vercel ...` from the linked repo when the MCP only returns CLI guidance.
- First Vercel CLI run required device-code login. Do not assume Vercel CLI auth is already present even if the Vercel MCP is available.
- Vercel CLI linked the project and added `.vercel` to `.gitignore`; keep `.vercel/` local-only.
- `vercel domains add analog-archive.com analogdb-repo` failed because the repo was already linked; the correct command was `vercel domains add analog-archive.com`.
- Adding domains in Vercel was not enough. Cloudflare DNS still needed `A` records to `76.76.21.21`.
- DNS propagation showed `www` before the apex in one local `dig` attempt; verify with `dig @1.1.1.1` before assuming the apex is broken.
- HTTPS briefly failed with `SSL_ERROR_SYSCALL` right after DNS started resolving. This cleared after explicitly assigning aliases and waiting for Vercel/TLS to settle.
- `vercel inspect analog-archive.com` showed the deployment but did not list the custom aliases in the alias section even after alias assignment; use direct `curl -I` checks as the source of truth for live serving.

Follow-up resolved in the next log entry:

- Add Vercel/custom-domain URLs to Supabase Auth redirect allow-list before asking testers to use password recovery or auth flows on the Vercel domain.

### 2026-05-09: Supabase Auth Redirects For Vercel Domains

Completed:

- Updated `supabase/config.toml` to include Vercel and custom-domain auth redirect URLs.
- Kept `site_url` on GitHub Pages so the current beta line does not move yet.
- Preserved existing remote redirects that were missing locally:
  - `https://dperabeles.github.io/analogdb/analog-db-dashboard-review.html`
  - `http://127.0.0.1:8000/reset-password.html`
- Pushed Supabase config to project `dqjjxxqruxxfsfoejdzl`.
- Verified idempotency with a second `supabase config push`, which returned:
  - `Remote API config is up to date.`
  - `Remote DB config is up to date.`
  - `Remote Auth config is up to date.`
  - `Remote Storage config is up to date.`

Auth redirect URLs added:

```text
https://analogdb-repo.vercel.app/analog-db-dashboard.html
https://analogdb-repo.vercel.app/forgot-password.html
https://analogdb-repo.vercel.app/reset-password.html
https://analog-archive.com/analog-db-dashboard.html
https://analog-archive.com/forgot-password.html
https://analog-archive.com/reset-password.html
https://www.analog-archive.com/analog-db-dashboard.html
https://www.analog-archive.com/forgot-password.html
https://www.analog-archive.com/reset-password.html
```

Validation commands used:

```bash
supabase config push --project-ref dqjjxxqruxxfsfoejdzl --yes
supabase config push --project-ref dqjjxxqruxxfsfoejdzl --yes
```

Errors / lessons:

- `supabase config push --linked --yes` failed because this Supabase CLI version does not support `--linked` on `config push`. Use `supabase config push --project-ref dqjjxxqruxxfsfoejdzl --yes`.
- The first config push revealed that remote Auth had redirects not present in local `supabase/config.toml`. Before treating local config as source of truth, compare the CLI diff and preserve remote-only allow-list entries unless intentionally removing them.
- Even with `--yes`, `supabase config push` printed the Auth diff and prompt text. In this CLI, the `y` confirmation was still handled automatically, but future agents should still read the diff before assuming the push is safe.

Open follow-up:

- Run a real password recovery smoke test on `https://analog-archive.com/forgot-password.html` with a controlled account before inviting testers to use the new domain for account recovery.

### 2026-05-09: New-User Equipment Autoseed Bug Investigation

Observed:

- A new account successfully passed the password-recovery/auth smoke test on the custom domain.
- During that test, the new account showed preloaded equipment that should not exist for a fresh user:
  - Cameras: `Canon 7`, `Mamiya M645J`, `Pentax Super Program`, `Pentax IQ Zoom 115M`, `Pentax PC-330`, plus `Canon 514XL`.
  - Lenses expected by the UI seed list: `Pentax-A 50mm f2.0`, `Pentax-A 70-210mm f4`, `Mamiya 55mm f2.8`, `Industar-61 53mm f2.8`.

Root cause evidence:

- `analog-db-dashboard.html` defines `SEED_CAMERAS` and `SEED_LENSES` near the camera catalog code.
- `loadCamerasCatalog()` queries `public.cameras`; when the result for the logged-in user is empty, it calls `seedCamerasToDb()`.
- `seedCamerasToDb()` uses `upsertCameraRemote(...)`, which writes each seed row with `owner_user_id: currentUserId()`.
- Live database aggregate confirmed the six seed cameras exist once per owner: each seed camera appeared with `18` copies across `18` owners.
- Camera/lens RLS is not the apparent leak source: policies constrain equipment by `owner_user_id = auth.uid()`.
- Lenses behave differently: `loadLensesCatalog()` falls back to `SEED_LENSES` in memory when the logged-in user's lenses table is empty. It does not call an equivalent `seedLensesToDb()` in the inspected code path.

Recommendation:

- Fix before deeper Next.js migration. This is current beta behavior and will continue to contaminate new accounts if left as-is.
- Remove remote autoseeding for authenticated Supabase users. New accounts should render `0` cameras and `0` lenses until the user adds equipment.
- Keep seed equipment only for no-Supabase/local-demo mode if still needed.
- Add a cleanup migration/query for beta users who received only the default seed cameras and have not actually used them in rolls.

Errors / lessons:

- Do not assume default equipment is only local demo data. In this code path, camera seed data is persisted remotely per user.
- Do not treat lenses and cameras as identical: cameras are inserted into Supabase; lenses are currently an in-memory fallback when no lens records exist.
- Before cleanup, check roll references. Deleting seeded cameras blindly could break `rolls.camera_id` references for users who already selected one of those seeded cameras.

Open follow-up:

- Implement a beta hotfix on the stable line, then bring it into `feature/nextjs-vercel-migration`.
- Add a regression test that confirms empty remote camera/lens catalogs stay empty for authenticated users.

### 2026-05-09: Equipment Autoseed Hotfix

Completed:

- Updated `analog-db-dashboard.html` so demo equipment seeds are only used when Supabase is unavailable.
- Removed the remote `seedCamerasToDb()` path that inserted private camera rows for every approved user with an empty catalog.
- Updated `loadLensesCatalog()` so `SEED_LENSES` are not shown when Supabase is active and the authenticated user's lens catalog is empty.
- Added regression checks in:
  - `tests/camera-quick-mode.test.js`
  - `tests/camera-lens-quick-add.test.js`

Validation commands used:

```bash
node --test tests/camera-quick-mode.test.js tests/camera-lens-quick-add.test.js
node --check auth-recovery.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
```

Existing data cleanup evidence:

- A database aggregate showed seed cameras already exist across user accounts.
- Some seed camera rows are referenced by `rolls.camera_id`, so deleting all matching rows blindly is unsafe.
- Unreferenced seed-camera rows can be considered cleanup candidates, but cleanup should be explicit and reviewed separately because users may have intentionally kept one of those camera models.

Errors / lessons:

- The hardcoded equipment was similar to the earlier film-stock issue only in that it lived in the HTML. The domain rule is different: film stocks are global catalog data; cameras and lenses are private user equipment and must not be globally seeded.

Open follow-up:

- Decide whether to run a guarded cleanup for unreferenced seed camera rows already inserted into beta user accounts.
