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

const mobileNav = read('src/features/navigation/mobile-bottom-nav.tsx');
assertIncludes(mobileNav, 'mobile-bottom-nav', 'mobile nav should expose the shared bottom-nav class');
assertIncludes(mobileNav, 'href: "/dashboard"', 'mobile nav should link to dashboard');
assertIncludes(mobileNav, 'href: "/rolls/new"', 'mobile nav should link to new roll flow');
assertIncludes(mobileNav, 'href: "/stats"', 'mobile nav should link to stats');
assertIncludes(mobileNav, 'href: "/timeline"', 'mobile nav should link to timeline');
assertIncludes(mobileNav, 'href: "/equipment"', 'mobile nav should link to equipment');
assertIncludes(mobileNav, 'aria-current={active === item.key ? "page" : undefined}', 'mobile nav should mark active route');

[
  ['src/app/dashboard/page.tsx', 'active="dashboard"'],
  ['src/app/rolls/new/page.tsx', 'active="new"'],
  ['src/app/stats/page.tsx', 'active="stats"'],
  ['src/app/timeline/page.tsx', 'active="timeline"'],
  ['src/app/equipment/page.tsx', 'active="equipment"'],
  ['src/app/admin/page.tsx', 'active="admin"'],
  ['src/app/rolls/[code]/page.tsx', 'active="detail"'],
  ['src/app/rolls/[code]/edit/page.tsx', 'active="edit"']
].forEach(([filePath, activeMarker]) => {
  const source = read(filePath);
  assertIncludes(source, 'MobileBottomNav', `${filePath} should render mobile bottom navigation`);
  assertIncludes(source, activeMarker, `${filePath} should pass the expected active state`);
});

const css = read('src/app/globals.css');
assertIncludes(css, '.mobile-bottom-nav', 'global CSS should style mobile bottom navigation');
assertIncludes(css, 'grid-template-columns: repeat(5, minmax(0, 1fr));', 'mobile nav should keep five stable columns');
assertIncludes(css, '.mobile-bottom-nav-item[aria-current="page"]', 'mobile nav should show active state');

console.log('next mobile navigation static checks passed');
