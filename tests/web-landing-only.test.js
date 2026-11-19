const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// Diego, 17-nov: until the web app is rebuilt like the app, the web is only
// the home page. The web app's pages send to it (their code stays), the
// pages the e-mails open keep working, and «Entrar» stays as an inactive
// «Webapp · Próximamente».

const root = path.join(__dirname, '..');
const read = (filePath) => fs.readFileSync(path.join(root, filePath), 'utf8');

const paused = read('src/lib/webapp-paused.ts');
const listed = [...paused.matchAll(/"(\/[a-z-]+)"/g)].map((m) => m[1]);

for (const page of ['/dashboard', '/rolls', '/stats', '/equipment', '/account', '/admin', '/timeline', '/database']) {
  assert.ok(listed.includes(page), `${page} is part of the paused web app`);
  assert.ok(fs.existsSync(path.join(root, 'src/app', page.slice(1))), `${page} keeps its code`);
}

// The pages the e-mails open are not the web app.
for (const page of ['/confirm', '/reset-password', '/forgot-password', '/privacy', '/terms', '/cookies', '/contact']) {
  assert.ok(!listed.includes(page), `${page} must keep working`);
}

const middleware = read('middleware.ts');
assert.ok(middleware.includes('isPausedWebappPath'), 'the middleware sends the paused pages home');
assert.ok(/NextResponse\.redirect\(/.test(middleware), 'it redirects, it does not render');
assert.ok(middleware.includes('applyGpc(request, '), 'Global Privacy Control still applies');

// After an e-mail, nothing points into the paused web app.
for (const file of [
  'src/features/auth/confirm-account.tsx',
  'src/features/auth/update-password-form.tsx',
  'src/features/auth/password-recovery-form.tsx',
]) {
  assert.ok(!read(file).includes('"/dashboard"'), `${file} should not send to the paused dashboard`);
}

const landing = read('src/features/landing/landing.tsx');
assert.ok(!landing.includes('<LandingAccess'), 'the home page has no sign-in while the web app is paused');
assert.ok(fs.existsSync(path.join(root, 'src/features/landing/landing-access.tsx')), 'the sign-in code stays');
assert.ok(landing.includes('aria-disabled="true"'), '«Entrar» stays, inactive');
assert.ok(landing.includes('t.pricing') && landing.includes('t.roadmap'), 'pricing and the roadmap are on the page');

const copy = read('src/features/landing/landing-copy.ts');
for (const text of ['Webapp · Próximamente', 'PRO · Próximamente', 'En camino', 'Apple Watch', 'Web app · Coming soon', 'PRO · Coming soon']) {
  assert.ok(copy.includes(text), `the copy says «${text}»`);
}
// No price is published until the store has one (ANA-147).
assert.ok(!/\$\s?\d|\d+\s?MXN/.test(copy), 'no price on the home page');
