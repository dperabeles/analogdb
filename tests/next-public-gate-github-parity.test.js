const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');

function read(filePath) {
  return fs.readFileSync(path.join(root, filePath), 'utf8');
}

function assertIncludes(source, needle, message) {
  assert.ok(source.includes(needle), message || `Expected to find ${needle}`);
}

const gate = read('src/features/auth/access-gate.tsx');
assertIncludes(gate, 'Track every roll from camera to archive.', 'public gate should match the GitHub Pages hero copy');
assertIncludes(gate, 'landing_metrics', 'public gate should hydrate the same landing metrics RPC as GitHub Pages');
assertIncludes(gate, 'gate-marquee', 'public gate should keep the GitHub Pages metrics marquee');
assertIncludes(gate, 'Diego Perabeles', 'public gate should include the GitHub Pages founder credit');
assertIncludes(gate, 'El display name será visible dentro de tu archivo', 'signup help copy should match GitHub Pages');

const css = read('src/app/globals.css');
assertIncludes(css, 'family=DM+Mono', 'global font import should keep DM Mono');
assertIncludes(css, 'font-family: Inter, ui-sans-serif, system-ui, sans-serif', 'public gate h1 should match the rendered GitHub Pages sans heading');
assertIncludes(css, '.gate-frame', 'public gate should use the GitHub Pages framed layout');
assertIncludes(css, 'width: min(1080px, 100%)', 'gate frame should match GitHub Pages max width');
assertIncludes(css, 'background: #14110d', 'gate shell should use the GitHub Pages dark access background');
assertIncludes(css, '.gate-panels .primary-action', 'gate buttons should be scoped to the access panel');

[
  'src/app/page.tsx',
  'src/app/dashboard/page.tsx',
  'src/app/stats/page.tsx',
  'src/app/timeline/page.tsx',
  'src/app/equipment/page.tsx',
  'src/app/admin/page.tsx',
  'src/app/rolls/new/page.tsx',
  'src/app/rolls/[code]/page.tsx',
  'src/app/rolls/[code]/edit/page.tsx'
].forEach((filePath) => {
  const source = read(filePath);
  assertIncludes(source, 'gate-shell', `${filePath} should render the public GitHub-style gate without the Next topbar`);
});

console.log('next public gate GitHub parity static checks passed');
