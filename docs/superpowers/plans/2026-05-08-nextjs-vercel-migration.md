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
- Deployment id: `dpl_5BZJnFo66sadYJ63q5bF1F52wEat`
- Deployment status: Ready
- Validated routes: `/`, `/analog-db-dashboard.html`, `/forgot-password.html`, `/reset-password.html`
- Still pending before tester use: add Vercel URLs to Supabase Auth redirect allow-list.

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

- [ ] **Step 4: Add Supabase auth redirect URLs**

Add the Vercel preview URL in Supabase Auth settings:

```text
https://<vercel-preview-host>/reset-password.html
https://<vercel-preview-host>/forgot-password.html
https://<vercel-preview-host>/analog-db-dashboard.html
```

Expected: password recovery links can return to the Vercel preview without being blocked by Supabase redirect allow-list rules.

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

- [ ] **Step 3: Assign product domains**

Recommended final mapping:

```text
analog-archive.com -> public landing
www.analog-archive.com -> root alias
app.analog-archive.com -> Vercel app
beta-next.analog-archive.com -> temporary migration preview
```

Expected: DNS and Supabase redirects are aligned before full cutover.

- [ ] **Step 4: Retire GitHub Pages only after verified parity**

Keep `main` stable until Vercel is the accepted production target.

Expected: no beta tester needs to export/import catalog data.

---

## Self-Review

- Spec coverage: deploy-in-parallel, shared Supabase data, Next.js migration, later React Native readiness, and no GitHub Pages interruption are all covered.
- Placeholder scan: no `TBD` or open-ended task placeholders remain.
- Type consistency: future TypeScript paths and environment variable names are consistent across tasks.
