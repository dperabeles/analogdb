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
assertIncludes(dashboard, '<AccessGate', 'dashboard should render login/signup gate when there is no session');
assertIncludes(dashboard, '<AccessStatus', 'dashboard should render pending/rejected/invalid states');
assertIncludes(dashboard, '<SignOutButton', 'approved shell should expose logout');

const gate = read('src/features/auth/access-gate.tsx');
assertIncludes(gate, 'signInWithPassword', 'gate should support email/password login');
assertIncludes(gate, 'router.replace("/dashboard")', 'successful login should leave the public gate and enter the dashboard');
assertIncludes(gate, 'signUp', 'gate should support beta access request');
assertIncludes(gate, "data: { display_name: displayName }", 'signup should preserve display_name metadata for the existing trigger');

const recovery = read('src/features/auth/password-recovery-form.tsx');
assertIncludes(recovery, 'resetPasswordForEmail', 'forgot-password route should send Supabase recovery email');
assertIncludes(recovery, '/reset-password', 'recovery email should return to the Next reset-password route');

const update = read('src/features/auth/update-password-form.tsx');
assertIncludes(update, 'updateUser({ password })', 'reset-password route should update the active recovery session password');

const middleware = read('middleware.ts');
assertIncludes(middleware, 'updateSupabaseSession', 'middleware should keep Supabase SSR cookies fresh');

console.log('next auth gates static checks passed');
