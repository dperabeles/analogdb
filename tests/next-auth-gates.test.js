const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');

function read(filePath) {
  return fs.readFileSync(path.join(root, filePath), 'utf8');
}

function assertFile(filePath) {
  assert.ok(fs.existsSync(path.join(root, filePath)), `${filePath} should exist`);
}

function assertIncludes(source, needle, message) {
  assert.ok(source.includes(needle), message || `Expected to find ${needle}`);
}

[
  'src/features/auth/access-gate.tsx',
  'src/features/auth/access-status.tsx',
  'src/features/auth/sign-out-button.tsx',
  'src/features/auth/password-recovery-form.tsx',
  'src/features/auth/update-password-form.tsx',
  'src/features/auth/profile.ts',
  'src/app/dashboard/page.tsx',
  'src/app/forgot-password/page.tsx',
  'src/app/reset-password/page.tsx',
  'middleware.ts'
].forEach(assertFile);

const dashboard = read('src/app/dashboard/page.tsx');
assertIncludes(dashboard, 'export const dynamic = "force-dynamic"', 'dashboard should stay runtime-rendered for session cookies');
assertIncludes(dashboard, 'getCurrentAccessProfile', 'dashboard should resolve access state server-side');
assertIncludes(dashboard, '<AccessGate', 'dashboard should send a reader without a session to the sign-in');
assertIncludes(dashboard, '<AccessStatus', 'dashboard should render pending/rejected/invalid states');

const appShell = read('src/features/navigation/app-shell.tsx');
assertIncludes(appShell, '<SignOutButton', 'approved shell should expose logout');

// DEC-013: the web is the home page and accounts are created in the app.
// Without a session the old pages go to the home page's sign-in, and no
// page on the web offers a sign-up form.
const gate = read('src/features/auth/access-gate.tsx');
assertIncludes(gate, 'redirect("/#acceso")', 'without a session the old pages should go to the home page sign-in');

const access = read('src/features/landing/landing-access.tsx');
assertIncludes(access, 'signInWithPassword', 'the home page should keep email/password sign-in');
assertIncludes(access, 'router.replace("/dashboard")', 'a successful sign-in should enter the dashboard');
assert.ok(!/auth\.signUp\b/.test(access), 'the home page should not create accounts');
assert.ok(!/auth\.signUp\b/.test(gate), 'the old gate should not create accounts');

const home = read('src/app/page.tsx');
assertIncludes(home, 'landing_metrics', 'the home page should show the public landing metrics');

const recovery = read('src/features/auth/password-recovery-form.tsx');
assertIncludes(recovery, 'resetPasswordForEmail', 'forgot-password route should send Supabase recovery email');
assertIncludes(recovery, '/reset-password', 'recovery email should return to the Next reset-password route');

const update = read('src/features/auth/update-password-form.tsx');
assert.match(update, /\bupdateUser\s*\(\s*\{\s*password\s*,?\s*\}\s*\)/, 'reset-password route should update the active recovery session password');

const middleware = read('middleware.ts');
assertIncludes(middleware, 'updateSupabaseSession', 'middleware should keep Supabase SSR cookies fresh');

console.log('next auth gates static checks passed');
