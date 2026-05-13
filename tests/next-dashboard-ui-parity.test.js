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

const dashboard = read('src/app/dashboard/page.tsx');
assertIncludes(dashboard, 'dashboard-masthead', 'dashboard should use an editorial masthead instead of a generic hero');
assertIncludes(dashboard, 'dashboard-summary-grid', 'dashboard should show compact archive summary metrics');
assertIncludes(dashboard, 'Archive Index', 'dashboard masthead should use archive-oriented language');

const rollList = read('src/features/rolls/roll-list.tsx');
assertIncludes(rollList, 'editorial-section-head rolls-header', 'roll archive should use the editorial section header');
assertIncludes(rollList, 'editorial-section-num', 'roll archive should include a roman-numeral section marker');
assertIncludes(rollList, 'roll-stock', 'roll rows should keep stock as the primary list field');
assertIncludes(rollList, 'manufacturer', 'roll rows should expose manufacturer context');

const css = read('src/app/globals.css');
assertIncludes(css, '.dashboard-masthead', 'CSS should style dashboard masthead');
assertIncludes(css, '.dashboard-summary-grid', 'CSS should style dashboard summary metrics');
assertIncludes(css, '.editorial-section-head', 'CSS should include reusable editorial section headers');
assertIncludes(css, 'grid-template-columns: 160px minmax(180px, 1.3fr)', 'desktop roll list should be dense and row-based');
assertIncludes(css, '.roll-card:last-child', 'row list should avoid trailing borders');

console.log('next dashboard UI parity static checks passed');
