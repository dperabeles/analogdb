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

function assertNotIncludes(source, needle, message) {
  assert.ok(!source.includes(needle), message || `Expected not to find ${needle}`);
}

const css = read('src/app/globals.css');
assertIncludes(css, 'family=DM+Mono', 'approved shell should keep the legacy mono font');
assertIncludes(css, 'family=Fraunces', 'approved shell should load a Fraunces editorial serif like the beta shell');
assertIncludes(css, '--paper: #f5ede0', 'approved shell should use the GitHub Pages paper canvas');
assertIncludes(css, '--paper-ink: #1a1510', 'approved shell should use the GitHub Pages paper ink');
assertIncludes(css, '.approved-shell .topbar', 'approved shell should scope the desktop sidebar styling');
assertIncludes(css, 'background: #2a2620', 'approved sidebar should use the editorial beta sidebar color');
assertIncludes(css, '.approved-shell .workspace', 'approved workspace should get the paper canvas');
assertIncludes(css, '.approved-shell .roll-code::before', 'roll IDs should keep the beta table chevron motif');

[
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
  assertIncludes(source, 'app-shell approved-shell', `${filePath} should use the approved editorial shell`);
});

const admin = read('src/app/admin/page.tsx');
assertNotIncludes(
  admin,
  'if (state !== "approved") {\n    return (\n      <main className="app-shell approved-shell">',
  'pending/rejected admin access states should remain on the dark access shell'
);

console.log('next editorial shell parity static checks passed');
