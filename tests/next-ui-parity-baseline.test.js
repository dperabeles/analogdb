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

const css = read('src/app/globals.css');
assertIncludes(css, 'fonts.googleapis.com/css2?family=DM+Mono', 'Next UI should load the legacy mono/editorial font stack');
assertIncludes(css, 'body::before', 'Next UI should include the subtle film-grain overlay');
assertIncludes(css, '--sidebar-width: 244px', 'desktop shell should match the legacy sidebar width');
assertIncludes(css, '@media (min-width: 721px)', 'desktop shell should have a dedicated breakpoint');
assertIncludes(css, 'position: fixed', 'desktop topbar should become a fixed sidebar');
assertIncludes(css, 'margin: 0 0 0 var(--sidebar-width)', 'workspace should clear the fixed desktop sidebar');

const appShell = read('src/features/navigation/app-shell.tsx');
assertIncludes(appShell, 'href: "/dashboard"', 'approved shell should keep Dashboard in the desktop nav');
assertIncludes(appShell, 'href: "/database"', 'approved shell should keep Database in the desktop nav');
assertIncludes(appShell, 'href: "/stats"', 'approved shell should keep Stats in the desktop nav');
assertIncludes(appShell, 'href: "/timeline"', 'approved shell should keep Timeline in the desktop nav');
assertIncludes(appShell, 'href: "/equipment"', 'approved shell should keep Equipment in the desktop nav');

[
  'src/app/database/page.tsx',
  'src/app/stats/page.tsx',
  'src/app/timeline/page.tsx',
  'src/app/equipment/page.tsx',
  'src/app/admin/page.tsx',
  'src/app/rolls/new/page.tsx',
  'src/app/rolls/[code]/page.tsx',
  'src/app/rolls/[code]/edit/page.tsx'
].forEach((filePath) => {
  const source = read(filePath);
  assertIncludes(source, '<AppShell', `${filePath} should use the shared approved shell`);
});

console.log('next UI parity baseline static checks passed');
