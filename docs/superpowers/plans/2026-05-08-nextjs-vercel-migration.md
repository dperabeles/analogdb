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

- [x] **Step 1: Add the Next.js project skeleton**

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

- [x] **Step 2: Add a minimal App Router shell**

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

- [x] **Step 3: Validate build**

Run:

```bash
npm install
npm run build
```

Expected: `next build` completes without TypeScript or route errors.

- [x] **Step 4: Commit shell**

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

- [x] **Step 1: Move public Supabase config to env variables**

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

- [x] **Step 2: Add Vercel environment variables**

Set these in Vercel for preview and production:

```text
NEXT_PUBLIC_SUPABASE_URL=https://dqjjxxqruxxfsfoejdzl.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<current publishable anon key>
```

Expected: preview and production deployments use the same Supabase project as GitHub Pages.

- [x] **Step 3: Commit Supabase foundation**

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

- [x] **Step 1: Migrate auth gates**

Implement login, signup pending state, rejected state, logout, and password recovery routes before moving roll data screens.

Expected: a beta tester can authenticate in Next.js and reach an empty dashboard shell.

- [x] **Step 2: Migrate roll read flows**

Implement roll list, filters, sort, and detail view using backward-compatible queries against existing Supabase tables.

Expected: data created from GitHub Pages appears in the Next.js preview.

- [x] **Step 3: Migrate roll write flows**

Implement create/edit roll with the same fields currently supported by `analog-db-dashboard.html`.

Expected: records created in Next.js remain visible and editable in GitHub Pages.

- [x] **Step 4: Migrate admin flows**

Implement pending/rejected/approved profile management after regular user flows are stable.

Expected: founder/admin workflows remain available before GitHub Pages is retired.

- [x] **Step 5: Commit each migrated feature separately**

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

### 2026-05-09: Existing Test Account Still Shows Seed Cameras

Observed:

- After the autoseed hotfix was deployed, the password-recovery test account no longer showed seed lenses, but still showed seed cameras.
- Database check for recent profiles showed the newest approved account created at `2026-05-09 04:26:42+00` has:
  - `6` cameras
  - `0` lenses
  - `0` rolls

Conclusion:

- This is expected for an account that opened the app before the hotfix was live. The old code inserted camera seeds into `public.cameras`; once inserted, the new frontend correctly reads them as real rows.
- Lenses disappeared because they were not persisted through the same path; they were only an in-memory fallback when the remote lens catalog was empty.
- The hotfix prevents future autoseeding, but does not delete already inserted camera rows.

Validation query used:

```sql
select
  p.user_id,
  p.status,
  p.created_at,
  count(distinct c.id) as cameras,
  count(distinct l.id) as lenses,
  count(distinct r.id) as rolls
from public.profiles p
left join public.cameras c on c.owner_user_id = p.user_id
left join public.lenses l on l.owner_user_id = p.user_id
left join public.rolls r on r.owner_user_id = p.user_id
group by p.user_id, p.status, p.created_at
order by p.created_at desc
limit 8;
```

Open follow-up:

- Run a guarded cleanup for accounts with seed cameras and no roll references.
- For the test account specifically, all 6 seed camera rows are safe cleanup candidates because it has `0` rolls.

### 2026-05-09: Initial Next.js Shell

Completed:

- Created the initial Next.js App Router shell under `src/app`.
- Added:
  - `package.json`
  - `package-lock.json`
  - `next.config.js`
  - `tsconfig.json`
  - `next-env.d.ts`
  - `src/app/layout.tsx`
  - `src/app/page.tsx`
  - `src/app/dashboard/page.tsx`
  - `src/app/globals.css`
- Updated `.gitignore` for Node/Next artifacts.
- Kept GitHub Pages as the active beta line; this shell is only for the migration branch.

Validation commands used:

```bash
npm install
npm run build
npm run typecheck
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npm audit --omit=dev
```

Validation result:

- `next build` passed with Next.js `16.2.6`.
- `tsc --noEmit` passed.
- Existing JS and Python regression tests passed.

Errors / lessons:

- The first `next build` failed because the initial `tsconfig.json` included all `**/*.ts` files, so TypeScript tried to check Supabase Edge Functions written for Deno. The fix was to scope Next TypeScript to `src/**/*.ts` and `src/**/*.tsx`, and exclude `supabase/functions`.
- A concurrent `npm run build` and `npm run typecheck` produced a transient `.next/types` missing-file error. Run `next build` first, then `typecheck`, or avoid running those two in parallel.
- `npm audit --omit=dev` reported 2 moderate vulnerabilities through `next -> postcss`, and suggested `npm audit fix --force`, which would install `next@9.3.3` as a breaking downgrade. Do not run that forced fix. Revisit after Next publishes a safe dependency update.

Open follow-up:

- Run the Next dev server locally when continuing UI work and verify `/` and `/dashboard`.
- Next task is Task 3: move Supabase public config into environment variables and add shared Supabase client foundations.

### 2026-05-09: Supabase Client Foundation For Next.js

Completed:

- Added public env helpers:
  - `src/lib/env.ts`
  - `.env.example`
- Added Supabase client factories:
  - `src/lib/supabase/client.ts`
  - `src/lib/supabase/server.ts`
- Added initial typed database contract:
  - `src/types/database.ts`
- Added TypeScript path alias `@/* -> src/*`.
- Scoped `tsconfig.json` to the Next app source and excluded `supabase/functions` so Deno Edge Functions are not typechecked by the Next app.
- Added Vercel environment variables:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- Vercel environments configured:
  - `Production`
  - `Development`
  - `Preview (feature/nextjs-vercel-migration)`

Validation commands used:

```bash
npm run typecheck
npm run build
npx --yes vercel env list
```

Validation result:

- `tsc --noEmit` passed.
- `next build` passed.
- `vercel env list` showed both Supabase variables in all intended Vercel environments.

Errors / lessons:

- TypeScript 6 reports `baseUrl` deprecation warnings, but path aliases still require it with this setup. Added `ignoreDeprecations: "6.0"` as a temporary compatibility setting.
- `vercel env add <name> preview --value ... --yes` still required a branch in agent/non-interactive mode. Use `vercel env add <name> preview feature/nextjs-vercel-migration --value ... --yes` for this migration branch.
- `NEXT_PUBLIC_` values are intentionally browser-visible. Do not put privileged backend keys in this pattern.

Open follow-up:

- Later replace the hand-written `src/types/database.ts` with generated Supabase types once the Next app begins using more tables and RPCs.

### 2026-05-09: Next.js Auth Gates

Completed:

- Migrated the first auth gate slice into the Next.js App Router.
- Added server-side access resolution against Supabase Auth and `public.profiles`.
- Added login/signup UI for the public state.
- Added pending, rejected, and invalid profile states.
- Added logout for authenticated states.
- Added `/forgot-password` and `/reset-password` routes for the Next app.
- Added Supabase SSR middleware so auth cookies stay fresh for server-rendered routes.
- Marked `/dashboard` as runtime-rendered because it depends on session cookies.
- Set `vercel.json` framework override to `nextjs` so Vercel no longer uses the earlier static-site `Other` preset.
- Re-saved `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in Vercel with `--no-sensitive` for Production, Development, and branch Preview.
- Redeployed the fixed branch preview:
  - `https://analogdb-repo-6t1zc87jd-arqdiegoperabeles-2865s-projects.vercel.app`
- Updated Supabase Auth redirect allow-list with clean Next routes:
  - `http://localhost:3000/reset-password`
  - `https://analogdb-repo.vercel.app/forgot-password`
  - `https://analogdb-repo.vercel.app/reset-password`
  - `https://analog-archive.com/forgot-password`
  - `https://analog-archive.com/reset-password`
  - `https://www.analog-archive.com/forgot-password`
  - `https://www.analog-archive.com/reset-password`

Validation commands used:

```bash
node --test tests/next-auth-gates.test.js
npm run build
npm run typecheck
supabase config push --project-ref dqjjxxqruxxfsfoejdzl --yes
supabase config push --project-ref dqjjxxqruxxfsfoejdzl --yes
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env list
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/dashboard
curl -sS -I http://127.0.0.1:3000/forgot-password
curl -sS -I http://127.0.0.1:3000/reset-password
npx --yes vercel redeploy https://analogdb-repo-mde7xr6pk-arqdiegoperabeles-2865s-projects.vercel.app --target preview
npx --yes vercel inspect https://analogdb-repo-6t1zc87jd-arqdiegoperabeles-2865s-projects.vercel.app --wait --timeout 90s
```

Validation result:

- `tests/next-auth-gates.test.js` passed.
- `next build` passed and reported `/dashboard` as dynamic.
- `tsc --noEmit` passed.
- Existing JS and Python regression tests passed.
- Second Supabase config push returned `Remote Auth config is up to date.`
- Local smoke test returned `200 OK` for `/dashboard`, `/forgot-password`, and `/reset-password` after branch Preview envs were corrected.
- Vercel redeploy `dpl_CViUASCx6VcRh5MS9SP1yixewJY9` returned `Ready`.

Errors / lessons:

- `display_name` can be null for real profiles, so auth UI types must allow a nullable display name and render a fallback.
- The first `next build` failed when `/dashboard` tried to prerender without local Supabase env vars. Session-dependent routes should be explicitly dynamic.
- The first Git-triggered Vercel preview for this task failed after a successful Next build because the project still used the static baseline `Other` framework preset and expected an output directory named `public`. Fix with `"framework": "nextjs"` in `vercel.json`.
- Saving `NEXT_PUBLIC_` env vars as Vercel sensitive/encrypted values made `vercel env pull` write empty values locally. For browser-public env vars, use `--no-sensitive`; they are intentionally public.
- Pulling Vercel envs creates a local `.env.local` that can include a temporary `VERCEL_OIDC_TOKEN`. Keep `.env.local` ignored and delete it after smoke tests.
- Direct HTTP smoke checks against protected Preview URLs return Vercel `401`; use deployment `Ready` plus local smoke, or disable/share preview protection intentionally before browser-level remote testing.
- Build/typecheck should stay sequential. Running them concurrently can produce noisy generated-type races.
- Keep GitHub Pages `.html` redirects and clean Next redirects side by side until the beta fully cuts over to Vercel.

Open follow-up:

- Browser-level smoke test the protected Vercel preview only after a share URL is available or Preview protection is intentionally disabled for this branch.
- Resolved in the next log entry: Task 4 Step 2 migrated roll read flows with shared Supabase data.

### 2026-05-09: Next.js Roll Read Flows

Completed:

- Migrated the first read-only roll archive slice into Next.js.
- Added `rolls_flat` to the typed Supabase database contract, preserving legacy column names such as `#`, `FILM STOCK`, `STATUS`, and `FRAME SETTINGS`.
- Added server-side queries against `public.rolls_flat` so Next.js reads the same compatibility view as GitHub Pages.
- Added row mapping and legacy-compatible normalization for:
  - `PUSH/PULL`
  - `FORMAT`
- Added dashboard roll list with:
  - total/active/stock KPIs
  - status counts
  - status filter
  - text search
  - sort modes for newest, started, finished, and rating
- Added read-only roll detail route:
  - `/rolls/[code]`
- Kept this step read-only. Create/edit remains Task 4 Step 3.

Validation commands used:

```bash
node --test tests/next-roll-read-flows.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/dashboard
curl -sS -I http://127.0.0.1:3000/rolls/AA-TEST
```

Validation result:

- New roll read-flow static test passed.
- `tsc --noEmit` passed.
- `next build` passed and reported `/dashboard` and `/rolls/[code]` as dynamic.
- Existing JS and Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for `/dashboard`.
- Local smoke for `/rolls/AA-TEST` returned `200 OK` to the public access gate when unauthenticated, confirming the protected route renders instead of crashing.
- Vercel preview `dpl_4rUNHPcQP9xVnC6erWYXJaQ2ZhpK` returned `Ready`:
  - `https://analogdb-repo-4ozqr1xbu-arqdiegoperabeles-2865s-projects.vercel.app`

Errors / lessons:

- The first roll-read test was too tightly coupled to where normalization lived. Normalization belongs in the row mapping/type layer, not the query module.
- `next dev` rewrites `next-env.d.ts` to reference `.next/dev/types/routes.d.ts`; restore it to `.next/types/routes.d.ts` before committing.
- Curling the local Next server from inside the sandbox can fail even when the server is listening. Running the local curl with approved network permissions worked.
- Pulling Vercel envs creates `.env.local`; delete it after smoke tests because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- After this branch deploys, browser-smoke the protected Preview with an approved tester session or a Vercel share URL.
- Resolved in the next log entry: Task 4 Step 3 migrated initial roll create/edit flows while keeping GitHub Pages compatibility.

### 2026-05-10: Next.js Roll Write Flows

Completed:

- Added read/write Server Actions for rolls:
  - `saveRollAction`
  - `deleteRollAction`
- Added create route:
  - `/rolls/new`
- Added edit route:
  - `/rolls/[code]/edit`
- Added a shared `RollForm` for create/edit.
- Added dashboard entry point to create a roll.
- Added detail-page actions to edit or delete the current roll.
- Expanded typed Supabase contracts for normalized write tables:
  - `film_stocks`
  - `labs`
  - `rolls`
- Preserved the GitHub Pages write contract:
  - upsert `film_stocks` by `manufacturer,name`
  - upsert `cameras` by `owner_user_id,maker,model`
  - upsert `labs` by `name`
  - upsert new `rolls` by `owner_user_id,code`
  - update existing rolls by `owner_user_id + originalCode`
- Kept exposure/frame settings out of this step. They remain readable through `FRAME SETTINGS`; editing them should be handled separately.

Validation commands used:

```bash
node --test tests/next-roll-write-flows.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/rolls/new
curl -sS -I http://127.0.0.1:3000/rolls/AA-TEST/edit
```

Validation result:

- New roll write-flow static test passed.
- `tsc --noEmit` passed.
- `next build` passed and reported `/rolls/new` and `/rolls/[code]/edit` as dynamic.
- Existing JS and Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for `/rolls/new` and `/rolls/AA-TEST/edit`.
- Vercel preview `dpl_thxHZkndz97PpADGMLTDt4kWu3Tj` returned `Ready`:
  - `https://analogdb-repo-96cbj7e2r-arqdiegoperabeles-2865s-projects.vercel.app`

Errors / lessons:

- The first `update()` attempt reused the insert payload, but Supabase's generated types correctly reject insert-only fields such as `owner_user_id`, `id`, and `created_at` on updates. Split insert/update payloads before calling `.update(...)`.
- The initial smoke test only validated unauthenticated rendering through the access gate. A real create/edit submit still needs an approved-session browser smoke test before treating this as tester-ready.
- `next dev` again rewrote `next-env.d.ts`; restore it before committing.
- Pulling Vercel envs creates `.env.local`; delete it after smoke tests because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- Resolved in the next log entry: browser-smoke create/edit flows with an approved tester session on Vercel Preview and GitHub Pages.
- Next task is Task 4 Step 4: migrate admin flows after regular roll flows are verified.

### 2026-05-10: Real Account Roll Write Smoke

Completed:

- User validated roll write flows with a real approved account.
- Confirmed changes made through the GitHub Pages beta are reflected in the Vercel/Next.js deployment.
- Confirmed changes made through the Vercel/Next.js deployment are reflected in the GitHub Pages beta.
- Tested with multiple rolls, not just a single smoke record.
- Confirmed the shared Supabase backend is behaving as intended during the parallel migration period.

Validation result:

- Roll create/edit data now has real cross-frontend confirmation.
- Task 4 Step 3 can be treated as validated with an approved-session browser smoke.

Errors / lessons:

- Local unauthenticated smoke checks were useful for route stability, but they were not enough to prove write compatibility.
- For shared-backend migration tasks, always validate both directions:
  - GitHub Pages writes visible in Vercel/Next.js.
  - Vercel/Next.js writes visible in GitHub Pages.

Open follow-up:

- Continue with Task 4 Step 4: migrate admin flows into Next.js.

### 2026-05-10: Next.js Admin Flows

Completed:

- Migrated the admin panel into Next.js under `/admin`.
- Added admin overview queries for:
  - pending profiles
  - approved profiles
  - rejected profiles
  - admin roster
  - admin actions
- Added Server Actions that reuse the existing legacy Supabase RPC contract:
  - `admin_set_profile_status`
  - `request_admin_action`
  - `cast_admin_action_vote`
- Added UI controls for:
  - approve pending user
  - reject pending user
  - reactivate rejected user back to pending
  - request admin promotion
  - request admin downgrade for non-founder admins
  - vote approve/reject on pending admin actions
- Added an Admin link in the Next dashboard only when the current approved profile has `role = admin`.
- Expanded typed Supabase contracts for:
  - `user_roles`
  - `admin_actions`
  - `admin_action_approvals`
  - admin RPCs
- Added regression coverage in `tests/next-admin-flows.test.js`.

Validation commands used:

```bash
node --test tests/next-admin-flows.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/admin
curl -sS http://127.0.0.1:3000/admin
npx --yes vercel inspect https://analogdb-repo-6o2hndcp5-arqdiegoperabeles-2865s-projects.vercel.app --wait --timeout 120s
```

Validation result:

- New admin-flow static test passed.
- `tsc --noEmit` passed.
- `next build` passed and reported `/admin` as dynamic.
- Existing JS and Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for `/admin`.
- Unauthenticated `/admin` smoke rendered the access gate instead of crashing.
- Vercel preview `dpl_8CZ2vrPW3EJuwPkCiyReDFLuZmwG` returned `Ready`:
  - `https://analogdb-repo-6o2hndcp5-arqdiegoperabeles-2865s-projects.vercel.app`
- Vercel build output included dynamic route assets for `admin` and `admin.rsc`.

Errors / lessons:

- The first admin-flow RED test correctly failed because `/admin` did not exist yet.
- The first implementation hid explicit profile status queries behind a helper, which made the static contract less auditable. Keep admin status queries explicit while this migration is still being reviewed.
- One early static assertion expected literal hidden-input values, but the implementation correctly passed status values through a reusable component prop. The assertion was adjusted to test the actual source contract.
- `next dev` again rewrote `next-env.d.ts`; restore it to `.next/types/routes.d.ts` before committing.
- Pulling Vercel envs created `.env.local`; it was deleted after smoke because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- After Vercel deploys this commit, smoke `/admin` with a real founder/admin session before using the Next admin panel for live approvals.
- Next migration task is Task 5: cutover readiness and parity checklist. Camera flows, stats/timeline views, mobile layout, and real admin-session validation remain outside the completed admin slice.

### 2026-05-10: Cutover Readiness Parity Audit

Completed:

- Started Task 5 Step 1 parity checklist.
- Audited current Next.js routes and feature modules against the cutover checklist.
- Confirmed the current Next.js route surface includes:
  - `/`
  - `/dashboard`
  - `/forgot-password`
  - `/reset-password`
  - `/rolls/new`
  - `/rolls/[code]`
  - `/rolls/[code]/edit`
  - `/admin`
- Confirmed GitHub Pages remains the stable beta line while this parity audit is incomplete.

Parity checklist status:

```text
login/logout: covered by Next auth gate and SignOutButton; needs real browser smoke on latest preview.
signup pending state: covered by Next signup and pending access status; needs real browser smoke on latest preview.
password recovery: covered by clean Next routes; earlier custom-domain smoke passed, but latest preview should be rechecked before tester expansion.
roll list: covered and previously validated with shared Supabase data.
roll create/edit: covered and validated by user with multiple real rolls across GitHub Pages and Vercel/Next.js.
camera flows: partially covered after the Equipment slice. Next now has dedicated camera/lens management, but still needs real approved-session browser smoke against Vercel and GitHub Pages.
stats/timeline views: not migrated yet.
admin approval/rejection/reactivation: implemented in Next, but still needs real founder/admin-session browser smoke before live admin use.
mobile layout: responsive CSS exists for current Next pages, but the legacy mobile-specific equipment/detail/admin UX is not fully migrated or browser-verified.
```

Validation commands used:

```bash
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/
curl -sS -I http://127.0.0.1:3000/dashboard
curl -sS -I http://127.0.0.1:3000/forgot-password
curl -sS -I http://127.0.0.1:3000/reset-password
curl -sS -I http://127.0.0.1:3000/rolls/new
curl -sS -I http://127.0.0.1:3000/admin
```

Validation result:

- `tsc --noEmit` passed.
- `next build` passed.
- Existing JS regression tests passed.
- Existing Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for:
  - `/`
  - `/dashboard`
  - `/forgot-password`
  - `/reset-password`
  - `/rolls/new`
  - `/admin`
- `Task 5 Step 1` remains unchecked because the checklist is not fully at parity yet.

Errors / lessons:

- Do not mark cutover readiness complete just because core auth/roll/admin routes build. Camera/equipment management, stats/timeline, mobile parity, and real admin-session smoke are still blockers.
- During local smoke, one direct `curl` GET to `/dashboard` failed immediately after successful HEAD checks, while the Next dev server continued running and logged successful route responses. Treat the HEAD checks and server logs as the useful local smoke evidence here; use browser-level smoke for final parity decisions.
- `next dev` again rewrote `next-env.d.ts`; restore it before committing.
- Pulling Vercel envs created `.env.local`; it was deleted after smoke because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- Resolved in the next log entry: dedicated camera/equipment management in Next.js.
- After equipment real-session smoke, migrate stats/timeline views and run browser-level mobile verification.

### 2026-05-10: Next.js Equipment Management

Completed:

- Added dedicated `/equipment` route in Next.js.
- Added server-side equipment overview queries for:
  - user cameras
  - user lenses
  - roll references for usage counts and safe removal behavior
- Added Server Actions for:
  - `saveCameraAction`
  - `saveLensAction`
  - `removeCameraAction`
  - `removeLensAction`
- Added UI for:
  - creating cameras
  - editing cameras
  - creating lenses
  - editing lenses
  - quick-mode visibility toggles
  - interchangeable-lens vs integrated-lens camera setting
  - removing unused equipment
  - hiding referenced equipment from quick mode instead of breaking roll history
- Added dashboard link to `/equipment` for approved users.
- Added responsive Equipment CSS for current desktop/mobile breakpoints.
- Added regression coverage in `tests/next-equipment-flows.test.js`.

Safe delete behavior:

- If a camera/lens is not referenced by any roll, the Next action deletes it from the user's private equipment table.
- If a camera/lens is referenced by existing rolls, the Next action sets `show_in_quick_mode: false` instead of deleting it. This keeps historical rolls intact while removing unwanted equipment from quick-add surfaces.

Validation commands used:

```bash
node --test tests/next-equipment-flows.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/equipment
curl -sS -I http://127.0.0.1:3000/dashboard
npx --yes vercel inspect https://analogdb-repo-gpkzc5bpn-arqdiegoperabeles-2865s-projects.vercel.app --wait --timeout 120s
```

Validation result:

- New equipment-flow static test passed.
- `tsc --noEmit` passed.
- `next build` passed and reported `/equipment` as dynamic.
- Existing JS and Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for `/equipment` and `/dashboard`.
- Vercel preview `dpl_48irz7f6wKj4y1heAJpboaRwLpV8` returned `Ready`:
  - `https://analogdb-repo-gpkzc5bpn-arqdiegoperabeles-2865s-projects.vercel.app`

Errors / lessons:

- The first equipment-flow RED test correctly failed because `/equipment` did not exist yet.
- TypeScript rejected reusing `Insert` payloads for equipment updates because optional insert-only fields like `id` and `created_at` can leak into `.update(...)`. Split camera/lens update payloads explicitly.
- Safe delete needs roll-reference awareness. Deleting referenced equipment would preserve DB integrity because `rolls.camera_id` and `rolls.lens_id` use `on delete set null`, but it would still erase useful history context from the user experience.
- `next dev` again rewrote `next-env.d.ts`; restore it before committing.
- Pulling Vercel envs created `.env.local`; it was deleted after smoke because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- Resolved in the next log entry: real approved-account smoke for camera create/edit across Vercel/Next.js and GitHub Pages.
- Still pending: lens create/edit smoke and hide/remove equipment smoke.
- Next implementation slice after equipment smoke should be stats/timeline views.

### 2026-05-10: Real Account Equipment Camera Smoke

Completed:

- User validated camera equipment writes with a real approved account.
- Confirmed cameras added through Vercel/Next.js are reflected in GitHub Pages.
- Confirmed cameras added through GitHub Pages are reflected in Vercel/Next.js.
- Confirmed the shared Supabase backend is behaving correctly for camera equipment during the parallel migration period.

Validation result:

- Camera create/sync path now has real cross-frontend confirmation.
- Equipment management is closer to cutover parity, but the full equipment checklist is not complete until lenses and hide/remove behavior are smoke-tested too.

Errors / lessons:

- Equipment parity needs per-entity validation. Camera sync passing does not automatically prove lens sync or safe hide/remove behavior.
- For migration slices that write shared data, keep validating both directions:
  - GitHub Pages writes visible in Vercel/Next.js.
  - Vercel/Next.js writes visible in GitHub Pages.

Open follow-up:

- Run real approved-account smoke for:
  - create/edit lens in Next and confirm GitHub Pages sees it
  - hide/remove equipment in Next and confirm roll history remains intact
- Next implementation slice after equipment smoke should be stats/timeline views.

### 2026-05-10: Next.js Stats And Timeline Views

Completed:

- Added protected `/stats` route in Next.js.
- Added protected `/timeline` route in Next.js.
- Added shared analytics query layer that reuses the existing `getRolls()` read flow.
- Added stats sections for:
  - total roll counters
  - film type
  - format
  - film stock leaders
  - lab leaders
  - camera leaders
  - locations
  - photo categories
  - tags
- Added timeline grouping by effective roll date:
  - `finished` date first
  - `started` date fallback
  - `Sin fecha` group for undated rolls
- Added dashboard navigation links to `/stats` and `/timeline`.
- Added responsive CSS for analytics lists and timeline rows.
- Added regression coverage in `tests/next-stats-timeline-flows.test.js`.

Validation commands used:

```bash
node --test tests/next-stats-timeline-flows.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js tests/next-stats-timeline-flows.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/stats
curl -sS -I http://127.0.0.1:3000/timeline
curl -sS -I http://127.0.0.1:3000/dashboard
```

Validation result:

- New stats/timeline static test passed.
- `tsc --noEmit` passed.
- `next build` passed and reported `/stats` and `/timeline` as dynamic routes.
- Existing JS and Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for:
  - `/stats`
  - `/timeline`
  - `/dashboard`
- Vercel preview `dpl_J3uN2GWkupUEWbAdr374zaMpZKsc` returned `Ready` for the stats/timeline code deployment:
  - `https://analogdb-repo-el7zsoks5-arqdiegoperabeles-2865s-projects.vercel.app`
- Stable branch alias for the latest `feature/nextjs-vercel-migration` preview:
  - `https://analogdb-repo-git-featu-3bc83d-arqdiegoperabeles-2865s-projects.vercel.app`

Errors / lessons:

- The first stats/timeline RED test correctly failed because `/stats` and `/timeline` did not exist yet.
- This slice is read-only analytics over the shared Supabase backend through `rolls_flat`; it should not affect beta data writes.
- Browser-level and mobile visual QA are still required before treating stats/timeline as cutover-ready.
- `next dev` again rewrote `next-env.d.ts`; restore it before committing.
- Pulling Vercel envs created `.env.local`; it was deleted after smoke because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- Run real approved-account browser smoke for `/stats` and `/timeline`.
- Continue pending equipment smoke:
  - create/edit lens in Next and confirm GitHub Pages sees it
  - hide/remove equipment in Next and confirm roll history remains intact

### 2026-05-12: Next.js Mobile Navigation Baseline

Completed:

- Added shared `MobileBottomNav` component for approved Next.js app routes.
- Added mobile bottom navigation links for:
  - Data
  - Nuevo
  - Stats
  - Timeline
  - Equipo
- Added active-route state with `aria-current="page"`.
- Rendered the mobile bottom nav on:
  - `/dashboard`
  - `/rolls/new`
  - `/rolls/[code]`
  - `/rolls/[code]/edit`
  - `/stats`
  - `/timeline`
  - `/equipment`
  - `/admin`
- Added responsive CSS so the bottom nav is fixed only on mobile and desktop remains unchanged.
- Added regression coverage in `tests/next-mobile-navigation.test.js`.

Validation commands used:

```bash
node --test tests/next-mobile-navigation.test.js
npm run typecheck
npm run build
```

Validation result:

- New mobile navigation static test passed.
- `tsc --noEmit` passed after cleaning stale generated `.next` types.
- `next build` passed and kept all current app routes available.
- Vercel preview `dpl_4kxPW6xgh3BCZkaWBXTcyhjLGVTJ` returned `Ready` for the mobile navigation deployment:
  - `https://analogdb-repo-2q9egj65f-arqdiegoperabeles-2865s-projects.vercel.app`
- Stable branch alias for the latest `feature/nextjs-vercel-migration` preview:
  - `https://analogdb-repo-git-featu-3bc83d-arqdiegoperabeles-2865s-projects.vercel.app`

Errors / lessons:

- The first `npm run typecheck` failed because `.next/types` contained duplicate generated files with names like `routes.d 2.ts` and `cache-life.d 2.ts`.
- `.next` is generated output and ignored by git. Deleting `.next` cleared the duplicate generated types and `npm run typecheck` passed immediately after.
- This change improves mobile navigation structure, but it does not replace real approved-session browser smoke on an actual phone viewport.

Open follow-up:

- Run approved-account mobile smoke against the Vercel preview for:
  - `/dashboard`
  - `/rolls/new`
  - `/stats`
  - `/timeline`
  - `/equipment`
  - `/admin` with founder account
- Confirm no bottom-nav overlap with long roll forms, equipment forms, and admin action cards.
- Continue pending equipment smoke:
  - create/edit lens in Next and confirm GitHub Pages sees it
  - hide/remove equipment in Next and confirm roll history remains intact

### 2026-05-12: Dashboard Login Server Error Fix

Issue:

- User reported a Next.js server error screen immediately after login.
- Browser showed digest / error id `2332510782`.
- Vercel logs for `GET /dashboard` showed:
  - `TypeError: a.trim is not a function`

Root cause:

- `rolls_flat."FORMAT"` returns integer values in production, for example:
  - `35`
  - `120`
  - `8`
- `normalizeFormatValue()` assumed `FORMAT` was a string and called `value.trim()` directly.
- Approved users hit this path after login because `/dashboard` loads roll data with `getRolls()`.

Fix:

- Updated `normalizeFormatValue()` to accept `string | number | null`.
- Normalized through `String(value).trim()` before applying format aliases.
- Added regression coverage in `tests/roll-format-normalization.test.js` for:
  - `35 -> 35mm`
  - `120 -> 120`
  - `8 -> 8`
  - `mapRollFlatRow()` with numeric `FORMAT`

Validation commands used:

```bash
supabase db query --linked "select id, \"#\" as code, \"FORMAT\" as format, pg_typeof(\"FORMAT\")::text as format_type from public.rolls_flat where \"FORMAT\" is not null order by id desc limit 20;"
node --test tests/roll-format-normalization.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js tests/next-stats-timeline-flows.test.js tests/next-mobile-navigation.test.js tests/roll-format-normalization.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
```

Validation result:

- Confirmed production `rolls_flat."FORMAT"` is `integer`.
- Regression test failed before the fix with `TypeError: value.trim is not a function`.
- Regression test passed after the fix.
- `tsc --noEmit` passed.
- `next build` passed.
- Existing JS and Python regression tests passed.
- Vercel preview `dpl_9GhBMvzANBxT5cyaH2wfZvfwUFnJ` returned `Ready` for the dashboard login fix:
  - `https://analogdb-repo-b0el02fn3-arqdiegoperabeles-2865s-projects.vercel.app`
- Recent Vercel error logs for `feature/nextjs-vercel-migration` showed no new dashboard errors immediately after deployment.

Errors / lessons:

- Do not trust generated database TypeScript types blindly for legacy compatibility views. Verify runtime values from Supabase for fields coming from `rolls_flat`.
- Any normalizer that calls string methods should coerce legacy view values defensively at the boundary.

Open follow-up:

- Resolved in the next log entry: user retried login successfully against the stable branch preview.

### 2026-05-12: Dashboard Login Fix Real-User Confirmation

Completed:

- User retried login after the dashboard format-normalization fix.
- Confirmed the Vercel/Next.js preview now allows the approved user to enter the app.
- Confirmed the previous server error screen with digest `2332510782` no longer blocks login.

Validation result:

- Dashboard login path is now real-user confirmed on the Vercel preview.
- The root-cause fix for numeric `rolls_flat."FORMAT"` values can be treated as validated by both automated tests and approved-account usage.

Errors / lessons:

- Real-user smoke was necessary here because unauthenticated `curl` checks cannot exercise the approved `/dashboard` data path behind the Vercel preview/session protections.

Open follow-up:

- Continue approved-account smoke for:
  - `/stats`
  - `/timeline`
  - `/equipment`
  - create/edit lens in Next and confirm GitHub Pages sees it
  - hide/remove equipment in Next and confirm roll history remains intact

### 2026-05-13: Real-User Parity Smoke And Admin Reactivation Fix

Completed:

- User validated that these Vercel/Next.js routes show the correct real account information:
  - `/dashboard`
  - `/stats`
  - `/timeline`
  - `/equipment`
- User confirmed visual/UI parity is not the current target yet; current target is data and functionality correctness first.
- User confirmed a lens created from Vercel/Next.js appears in GitHub Pages.
- Confirmed lens create path has cross-frontend parity from Vercel to GitHub Pages.

Product decision:

- Do not invite beta testers to the Vercel preview yet.
- Tester expansion is blocked until the Vercel/Next.js UI is visually equal to or better than the current GitHub Pages experience.
- Treat the future UI pass as a required upgrade, not a cosmetic nice-to-have.

Issue:

- User reported an error when using the admin reactivation action.
- Vercel logs for `POST /admin` showed:
  - `Error: {"code":"P0001","details":null,"hint":null,"message":"invalid status"}`
  - digest `2511507339@E394`

Root cause:

- The Next.js rejected-user admin card sent `status="pending"` for Reactivar.
- The real remote Supabase RPC `public.admin_set_profile_status(uuid,text)` currently accepts only:
  - `approved`
  - `rejected`
- The local schema/migration files include a newer `pending`-allowed definition, but that definition is not what the linked remote database is currently running.

Fix:

- Changed the Next.js rejected-user Reactivar action to send `status="approved"`.
- Tightened `tests/next-admin-flows.test.js` so it specifically checks the `RejectedUsers` block reactivates to approved, instead of matching any unrelated approved status in the admin panel.

Validation commands used:

```bash
npx --yes vercel logs --level error --since 2h --branch feature/nextjs-vercel-migration --limit 50 --expand
supabase db query --linked "select pg_get_functiondef('public.admin_set_profile_status(uuid,text)'::regprocedure) as definition;"
node --test tests/next-admin-flows.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js tests/next-stats-timeline-flows.test.js tests/next-mobile-navigation.test.js tests/roll-format-normalization.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
```

Validation result:

- Confirmed the Vercel admin error came from invalid `pending` status.
- Confirmed linked Supabase RPC currently rejects `pending`.
- New admin-flow assertion failed before the fix and passed after the fix.
- `tsc --noEmit` passed.
- `next build` passed.
- Existing JS and Python regression tests passed.
- Vercel preview `dpl_AZrZmk5AxEZKTHWvaRPDfiqqYvim` returned `Ready` for the admin reactivation fix:
  - `https://analogdb-repo-ks3m32nhn-arqdiegoperabeles-2865s-projects.vercel.app`
- Recent Vercel error logs for `feature/nextjs-vercel-migration` showed no new admin errors immediately after deployment.

Errors / lessons:

- Local migration files can drift from the real linked Supabase function definition. For admin/security flows, verify the remote function definition before assuming local schema is current.
- Static assertions should target the specific component block under test; broad string checks can pass because the same literal exists elsewhere in the file.

Open follow-up:

- User should retry the admin Reactivar action after deployment.
- Remaining equipment smoke:
  - create/edit lens in GitHub Pages and confirm Vercel sees it
  - hide/remove equipment in Next and confirm roll history remains intact
- Resolved in the next log entry: started UI parity/upgrade baseline before inviting any beta testers to Vercel.

### 2026-05-13: UI Parity Baseline Shell

Completed:

- Started the UI parity/upgrade pass required before inviting beta testers to Vercel.
- Used the current GitHub Pages app and local design system as the visual reference.
- Added a desktop sidebar-style shell for approved Next.js routes using the existing `topbar` markup.
- Added full desktop navigation links across approved routes:
  - Dashboard
  - Nuevo
  - Stats
  - Timeline
  - Equipo
  - Admin where available
- Kept the mobile bottom nav from the previous slice.
- Added subtle film-grain overlay to move the Next.js UI closer to the current darkroom/editorial feel.
- Adjusted core Next.js tokens toward the existing darkroom palette.
- Added `DM Mono` and `Inter` font loading for closer parity with GitHub Pages.
- Added regression coverage in `tests/next-ui-parity-baseline.test.js`.

Validation commands used:

```bash
node --test tests/next-ui-parity-baseline.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js tests/next-stats-timeline-flows.test.js tests/next-mobile-navigation.test.js tests/next-ui-parity-baseline.test.js tests/roll-format-normalization.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/
curl -sS -I http://127.0.0.1:3000/dashboard
curl -sS -I http://127.0.0.1:3000/stats
```

Validation result:

- New UI parity baseline static test passed.
- `tsc --noEmit` passed.
- `next build` passed.
- Existing JS and Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for:
  - `/`
  - `/dashboard`
  - `/stats`
- Vercel preview `dpl_CzX5w6PLNK7S94nJP6YAeRgVcix6` returned `Ready` for the UI parity shell:
  - `https://analogdb-repo-484ijmq9i-arqdiegoperabeles-2865s-projects.vercel.app`
- Recent Vercel error logs for `feature/nextjs-vercel-migration` showed no new errors immediately after deployment.

Errors / lessons:

- The first local `/dashboard` smoke returned `500` because Supabase preview env vars were not loaded locally. Pulling preview envs fixed local smoke.
- `next dev` again rewrote `next-env.d.ts`; restored it before committing.
- Pulling Vercel envs created `.env.local`; it was deleted after smoke because it can include a temporary `VERCEL_OIDC_TOKEN`.
- This is only the first visual baseline. It improves the shell and navigation but does not yet make every view visually equal to or better than GitHub Pages.

Open follow-up:

- Run approved-session visual smoke on Vercel for:
  - `/dashboard`
  - `/stats`
  - `/timeline`
  - `/equipment`
  - `/admin`
- Continue UI parity slices for:
  - dashboard cards/list density
  - roll detail/editor visual parity
  - stats/timeline editorial sections
  - equipment/admin polish

### 2026-05-13: Dashboard UI Parity Density Pass

Completed:

- Continued the UI parity/upgrade work with a focused dashboard slice.
- Replaced the generic dashboard hero with an editorial `dashboard-masthead`.
- Added compact dashboard archive metrics for:
  - total rolls
  - active rolls
  - stock count
  - source/Supabase sync state
- Changed the roll archive header to use the roman-numeral editorial section pattern.
- Converted the desktop roll archive from repeated large cards into a denser row-based archive list.
- Added manufacturer context below each film stock in the roll list.
- Kept mobile roll cards readable and card-based so the density pass does not damage small screens.
- Added static regression coverage in `tests/next-dashboard-ui-parity.test.js`.

Validation commands used:

```bash
node --test tests/next-dashboard-ui-parity.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js tests/next-stats-timeline-flows.test.js tests/next-mobile-navigation.test.js tests/next-ui-parity-baseline.test.js tests/next-dashboard-ui-parity.test.js tests/roll-format-normalization.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS -I http://127.0.0.1:3000/
curl -sS -I http://127.0.0.1:3000/dashboard
curl -sS -I http://127.0.0.1:3000/stats
curl -sS -I http://127.0.0.1:3000/timeline
curl -sS -I http://127.0.0.1:3000/equipment
```

Validation result:

- New dashboard UI parity static test passed.
- `tsc --noEmit` passed after clearing stale generated `.next` output.
- `next build` passed.
- Existing JS and Python regression tests passed.
- Local smoke with Vercel Preview envs returned `200 OK` for:
  - `/`
  - `/dashboard`
  - `/stats`
  - `/timeline`
  - `/equipment`
- Browser smoke against local `/dashboard` showed no framework error overlay and no console errors in the unauthenticated access state.
- Vercel preview `dpl_HxVdo4S581Y9TEkZDdksgmGwm1hQ` returned `Ready` for the dashboard density pass:
  - `https://analogdb-repo-8i5u2yauo-arqdiegoperabeles-2865s-projects.vercel.app`
  - branch alias: `https://analogdb-repo-git-featu-3bc83d-arqdiegoperabeles-2865s-projects.vercel.app`
- Recent Vercel error logs for `feature/nextjs-vercel-migration` showed no errors immediately after deployment.

Errors / lessons:

- `.next` contained duplicate generated type files such as `cache-life.d 2.ts` and `routes.d 2.ts`, which made typecheck fail with duplicate identifier errors. Deleting generated `.next` output fixed the problem.
- Browser smoke without an approved auth session can only validate the access screen and route health. The real dashboard visual state still needs approved-user review on Vercel after deployment.
- `next dev` again rewrote `next-env.d.ts`; restored it before committing.
- Pulling Vercel envs created `.env.local`; it was deleted after smoke because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- User should review the authenticated dashboard visually on Vercel after deployment.
- Continue visual parity slices for:
  - roll detail/editor
  - stats/timeline
  - equipment
  - admin

### 2026-05-13: Rejected Wrong Editorial Paper Shell

Completed:

- User rejected the previous light paper/Fraunces approved-shell direction and clarified that it is not the GitHub beta archive design.
- Saved the rule in Codex memory: never use that light paper/Fraunces shell again for Analog Archive.
- Reverted the wrong design commits:
  - `aa72f14 docs: record approved shell preview`
  - `0cc180e feat: align approved shell with beta editorial UI`
- Removed the rejected `approved-shell` / paper / Fraunces direction from the branch.
- Removed `tests/next-editorial-shell-parity.test.js` because it encoded the wrong target.

Validation commands used:

```bash
rg -n "approved-shell|Fraunces|--paper|next-editorial-shell-parity|Approved Editorial Paper Shell" src tests docs/superpowers/plans/2026-05-08-nextjs-vercel-migration.md
node --test tests/next-ui-parity-baseline.test.js tests/next-dashboard-ui-parity.test.js
npm run typecheck
npm run build
gh api repos/dperabeles/analogdb/pages
```

Validation result:

- Search confirmed the rejected design tokens/classes/tests are no longer present after revert.
- UI parity baseline and dashboard UI parity static tests passed.
- `tsc --noEmit` passed.
- `next build` passed.
- GitHub Pages source of truth confirmed:
  - Pages URL: `https://dperabeles.github.io/analogdb/`
  - Runtime URL: `https://dperabeles.github.io/analogdb/analog-db-dashboard.html`
  - Browser title: `Analog Database`
  - Public access screen is the dark beta access design, with no console errors in browser verification.

Errors / lessons:

- Do not infer or invent an editorial direction from partial CSS snippets.
- Do not use the light paper/Fraunces design direction again. It was explicitly rejected.
- Before the next UI parity change, verify the real GitHub Pages beta visually and structurally, then match that exact design.
- The target is the current GitHub Pages beta archive UI, not a new redesign.

Open follow-up:

- Verify the current GitHub Pages beta UI directly before making any more visual changes.
- Capture the real design reference from `analog-db-dashboard.html` and/or live GitHub Pages.
- Then continue with exact parity only.

### 2026-05-13: GitHub Public Gate Parity Pass

Completed:

- Started the corrected UI parity work using GitHub Pages as the visual source of truth.
- Verified the live GitHub Pages public gate in browser before editing:
  - `https://dperabeles.github.io/analogdb/analog-db-dashboard.html`
  - title `Analog Database`
  - dark centered beta access frame
  - no console errors
- Rebuilt the Next.js public gate to match the GitHub Pages public access screen:
  - dark `#14110d` page background
  - centered `1080px` framed gate
  - left hero copy: `Track every roll from camera to archive.`
  - right login/request access panels
  - same forgot-password link text
  - same display-name help copy
  - same founder credit
  - same public metrics marquee pattern
- Added client-side `landing_metrics` RPC hydration with a safe fallback, matching the GitHub Pages public metric behavior.
- Removed the Next.js generic topbar from public unauthenticated routes and route `/` so the public view starts directly on the GitHub-style gate.
- Updated public unauthenticated routes for:
  - `/`
  - `/dashboard`
  - `/stats`
  - `/timeline`
  - `/equipment`
  - `/admin`
  - `/rolls/new`
  - `/rolls/[code]`
  - `/rolls/[code]/edit`
- Added static regression coverage in `tests/next-public-gate-github-parity.test.js`.

Validation commands used:

```bash
node --test tests/next-public-gate-github-parity.test.js tests/next-auth-gates.test.js tests/next-ui-parity-baseline.test.js tests/next-dashboard-ui-parity.test.js
npm run typecheck
npm run build
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-public-gate-github-parity.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js tests/next-stats-timeline-flows.test.js tests/next-mobile-navigation.test.js tests/next-ui-parity-baseline.test.js tests/next-dashboard-ui-parity.test.js tests/roll-format-normalization.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
```

Rendered browser verification:

- Opened GitHub Pages and local Next.js sequentially in the browser to avoid tab reuse confusion.
- GitHub Pages:
  - URL: `https://dperabeles.github.io/analogdb/analog-db-dashboard.html`
  - title: `Analog Database`
  - hero, forgot-password link, and founder credit present
  - no console errors
- Local Next.js:
  - URL: `http://127.0.0.1:3000/`
  - title: `Analog Archive`
  - hero, forgot-password link, and founder credit present
  - no console errors
- Visual correction made from rendered evidence: the H1 was changed back to the heavy sans look seen on live GitHub Pages instead of using a serif heading from source-code inference.

Validation result:

- New public gate GitHub parity static test passed.
- Existing auth gate, UI parity, and dashboard parity tests passed.
- `tsc --noEmit` passed.
- `next build` passed.
- Full JS regression suite passed: 14/14 tests.
- Python regression suite passed: 16/16 tests.

Errors / lessons:

- Browser tab reuse initially made the GitHub/Next comparison point both entries at local Next.js. Re-ran the check sequentially in one tab and used only the corrected result.
- Do not trust only inline CSS/source when rendered GitHub Pages differs. The visual reference is the live rendered GitHub page.
- `next dev` again rewrote `next-env.d.ts`; restored it before committing.
- Pulling Vercel envs created `.env.local`; it was deleted after smoke because it can include a temporary `VERCEL_OIDC_TOKEN`.

Open follow-up:

- Deploy this public gate parity pass to Vercel.
- User should compare the public login/access screen against GitHub Pages.
- Next exact parity target should be the authenticated GitHub dashboard shell, verified from the real beta state before edits.

### 2026-05-13: Vercel Preview Verification for GitHub Public Gate

Completed:

- Pushed the corrected public gate parity work to `feature/nextjs-vercel-migration`.
- Confirmed the Vercel preview deployment for the branch is ready:
  - deployment id: `dpl_3AD5CUU59ukRHs5v4hm1TgQWZYEK`
  - deployment URL: `https://analogdb-repo-fw0j59rb7-arqdiegoperabeles-2865s-projects.vercel.app`
  - branch alias: `https://analogdb-repo-git-featu-3bc83d-arqdiegoperabeles-2865s-projects.vercel.app`
  - target: `preview`
  - status: `Ready`
- Checked recent Vercel error logs for `feature/nextjs-vercel-migration`; no recent error logs were found.

Validation commands used:

```bash
npx --yes vercel inspect https://analogdb-repo-fw0j59rb7-arqdiegoperabeles-2865s-projects.vercel.app
npx --yes vercel logs --level error --since 30m --branch feature/nextjs-vercel-migration --limit 20 --expand
```

Validation result:

- Vercel preview is live and ready.
- No runtime error logs were reported for the branch in the checked window.

Errors / lessons:

- The design target remains the live GitHub Pages beta and `analog-db-dashboard.html`.
- Do not introduce any alternate visual direction while migrating. Match GitHub first, then improve only after parity is reached and approved.

Open follow-up:

- Compare the Vercel public access screen against GitHub Pages in the browser.
- Next migration task: authenticated dashboard parity against the real GitHub beta dashboard state.

### 2026-05-13: Login Redirect Fix After Public Gate Parity

Issue reported:

- User could submit login from the Vercel public gate, but the page stayed loading and did not enter the app.

Root cause:

- The login flow called `router.refresh()` after a successful `signInWithPassword`, but did not navigate away from `/`.
- The `/` route always renders the public access gate, so a successful login from that route could remain visually stuck on the login gate.
- The `busy` state also stayed set to `login`, which could leave the button showing `Entrando...` while the user remained on the public page.

Completed:

- Updated successful login behavior to call `router.replace("/dashboard")` before `router.refresh()`.
- Added regression coverage in `tests/next-auth-gates.test.js` so successful login must leave the public gate and enter the dashboard.

Validation commands used:

```bash
node --test tests/next-auth-gates.test.js
node --test tests/next-auth-gates.test.js tests/next-public-gate-github-parity.test.js tests/next-ui-parity-baseline.test.js tests/next-dashboard-ui-parity.test.js
npm run typecheck
npm run build
npx --yes vercel logs --level error --since 30m --branch feature/nextjs-vercel-migration --limit 50 --expand
```

Validation result:

- New failing test reproduced the missing redirect before the fix.
- Auth gate regression test passed after the fix.
- Public gate parity, UI parity baseline, and dashboard parity static tests passed.
- `tsc --noEmit` passed.
- `next build` passed.
- No recent Vercel error logs were found for the branch during investigation.

Errors / lessons:

- Public gate parity must preserve real auth navigation behavior, not only visual parity.
- `router.refresh()` is not enough when the current route is a public-only landing route.

Open follow-up:

- Push the fix and verify the Vercel preview deployment.
- User should retry login on the branch preview.

### 2026-05-13: Vercel Verification After Login Redirect Fix

Completed:

- Pushed login redirect fix commit `a6e0f79` to `feature/nextjs-vercel-migration`.
- Confirmed Vercel generated a new preview deployment for the fix:
  - deployment id: `dpl_FVDXF5B1sbgSvTasYHGTHPzzaRNs`
  - deployment URL: `https://analogdb-repo-18t8b8rrt-arqdiegoperabeles-2865s-projects.vercel.app`
  - branch alias: `https://analogdb-repo-git-featu-3bc83d-arqdiegoperabeles-2865s-projects.vercel.app`
  - target: `preview`
  - status: `Ready`
- Checked recent Vercel error logs for `feature/nextjs-vercel-migration`; no recent error logs were found.

Validation commands used:

```bash
npx --yes vercel inspect https://analogdb-repo-18t8b8rrt-arqdiegoperabeles-2865s-projects.vercel.app
npx --yes vercel logs --level error --since 10m --branch feature/nextjs-vercel-migration --limit 50 --expand
```

Validation result:

- The branch preview containing the login redirect fix is live.
- No recent runtime errors were reported by Vercel logs.

Open follow-up:

- User should retry login on the branch alias.

### 2026-05-13: Authenticated Dashboard GitHub Parity Pass

Completed:

- Started the authenticated UI parity pass from the real GitHub beta source in `analog-db-dashboard.html`.
- Added a reusable approved-session shell in `src/features/navigation/app-shell.tsx`:
  - dark editorial sidebar class `ed-sidebar`
  - numbered nav items via `ed-nav-num`
  - sidebar account card
  - shared mobile bottom nav
  - desktop archive location bar
- Updated `/dashboard` to use the GitHub beta dashboard language and structure:
  - masthead: `Cuaderno de laboratorio`
  - summary: active rolls and historical archive count
  - CTA copy: `+ Cargar rollo nuevo`
- Added `src/features/rolls/dashboard-overview.tsx` for GitHub-style dashboard sections:
  - Section I: `Tu film, de un vistazo`
  - format count grid
  - favorite stock leaderboard
  - Section II: `Tu film, en curso`
  - three workflow columns: En cámara, Por revelar, En revelado
  - roll workflow cards linking to detail routes
- Updated CSS to bring the dashboard closer to the GitHub dark editorial UI:
  - sidebar/account widget styling
  - masthead styling
  - index grid styling
  - stock rows
  - workflow columns
  - workflow roll cards
  - responsive desktop/mobile behavior
- Updated static regression tests so navigation assertions follow the new shared approved shell instead of assuming every route owns its own nav markup.

Validation commands used:

```bash
node --test tests/next-dashboard-ui-parity.test.js
node --test tests/next-auth-gates.test.js tests/next-public-gate-github-parity.test.js tests/next-ui-parity-baseline.test.js tests/next-dashboard-ui-parity.test.js tests/next-mobile-navigation.test.js
npm run typecheck
npm run build
npx --yes vercel env pull .env.local --environment=preview --git-branch feature/nextjs-vercel-migration --yes
npm run dev -- --hostname 127.0.0.1 --port 3000
curl -sS http://127.0.0.1:3000/
curl -sS http://127.0.0.1:3000/dashboard
node --test auth-recovery.test.js tests/camera-lens-quick-add.test.js tests/camera-quick-mode.test.js tests/next-auth-gates.test.js tests/next-public-gate-github-parity.test.js tests/next-roll-read-flows.test.js tests/next-roll-write-flows.test.js tests/next-admin-flows.test.js tests/next-equipment-flows.test.js tests/next-stats-timeline-flows.test.js tests/next-mobile-navigation.test.js tests/next-ui-parity-baseline.test.js tests/next-dashboard-ui-parity.test.js tests/roll-format-normalization.test.js
python3 -m unittest tests/test_rejected_admin_ui.py tests/test_film_catalog.py tests/test_exposure_settings.py
```

Validation result:

- New dashboard parity test failed before implementation and passed after the dashboard shell/overview changes.
- Focused auth/public/UI/dashboard/mobile tests passed.
- `tsc --noEmit` passed.
- `next build` passed.
- Local dev smoke for `/` and `/dashboard` returned the expected public gate for unauthenticated access.
- Full JS regression suite passed: 14/14 tests.
- Python regression suite passed: 16/16 tests.

Errors / lessons:

- Moving navigation into a shared approved shell broke several static tests that still searched only `dashboard/page.tsx`. Updated those tests to assert against the actual source of truth: `AppShell`.
- `next dev` rewrote `next-env.d.ts`; restored it before commit.
- Pulling Vercel envs created `.env.local`; deleted it after smoke because it can contain temporary auth material.

Open follow-up:

- Commit and deploy this dashboard parity pass to Vercel.
- User should compare authenticated dashboard on Vercel against GitHub beta.
- Next UI parity pass should cover Stats, Timeline, and Equipment with the same shared approved shell.

### 2026-05-13: Vercel Verification After Dashboard Parity Pass

Completed:

- Pushed dashboard parity commit `9e21d72` to `feature/nextjs-vercel-migration`.
- Confirmed Vercel generated a new preview deployment:
  - deployment id: `dpl_64vJtPPECnFSmbWPTswLhUnhrzdW`
  - deployment URL: `https://analogdb-repo-835doylm7-arqdiegoperabeles-2865s-projects.vercel.app`
  - branch alias: `https://analogdb-repo-git-featu-3bc83d-arqdiegoperabeles-2865s-projects.vercel.app`
  - target: `preview`
  - status: `Ready`
- Checked recent Vercel error logs for `feature/nextjs-vercel-migration`; no recent error logs were found.

Validation commands used:

```bash
npx --yes vercel inspect https://analogdb-repo-835doylm7-arqdiegoperabeles-2865s-projects.vercel.app
npx --yes vercel logs --level error --since 10m --branch feature/nextjs-vercel-migration --limit 50 --expand
```

Validation result:

- The Vercel preview containing the dashboard parity pass is live and ready.
- No recent runtime errors were reported by Vercel logs.

Open follow-up:

- User should compare the authenticated dashboard in Vercel against the current GitHub beta.
- Continue exact GitHub parity on Stats, Timeline, and Equipment after dashboard review.
