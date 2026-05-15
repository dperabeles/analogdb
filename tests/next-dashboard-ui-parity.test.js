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
assertIncludes(dashboard, 'Cuaderno de', 'dashboard masthead should match the GitHub beta notebook heading');
assertIncludes(dashboard, 'DashboardOverview', 'dashboard should render the GitHub-style index and workflow overview');

const appShell = read('src/features/navigation/app-shell.tsx');
assertIncludes(appShell, 'ed-sidebar', 'approved shell should use the GitHub beta editorial sidebar class');
assertIncludes(appShell, 'ed-nav-num', 'approved shell nav should keep GitHub-style numbered nav items');
assertIncludes(appShell, 'sidebar-account-card', 'approved shell should keep the GitHub beta account widget');

const rollList = read('src/features/rolls/roll-list.tsx');
assertIncludes(rollList, 'editorial-section-head rolls-header', 'roll archive should use the editorial section header');
assertIncludes(rollList, 'editorial-section-num', 'roll archive should include a roman-numeral section marker');
assertIncludes(rollList, 'database-roll-main', 'database rows should keep stock as the primary table field');
assertIncludes(rollList, 'manufacturer', 'roll rows should expose manufacturer context');
assertIncludes(rollList, 'rolls={rolls}', 'database filters should receive rolls to populate camera/lab options like GitHub beta');

const dashboardOverview = read('src/features/rolls/dashboard-overview.tsx');
assertIncludes(dashboardOverview, 'ed-index-grid', 'dashboard overview should match the GitHub beta index grid');
assertIncludes(dashboardOverview, 'ed-workflow', 'dashboard overview should match the GitHub beta workflow columns');
assertIncludes(dashboardOverview, 'Tu film, <em>de un vistazo</em>', 'dashboard section I copy should match GitHub');
assertIncludes(dashboardOverview, 'Tu film, <em>en curso</em>', 'dashboard section II copy should match GitHub');
assertIncludes(dashboardOverview, 'Cargar rollo', 'workflow should keep the GitHub dashboard add-roll language');

const css = read('src/app/globals.css');
assertIncludes(css, '.dashboard-masthead', 'CSS should style dashboard masthead');
assertIncludes(css, '.dashboard-summary-grid', 'CSS should style dashboard summary metrics');
assertIncludes(css, '.editorial-section-head', 'CSS should include reusable editorial section headers');
assertIncludes(css, '.ed-sidebar', 'CSS should style the GitHub beta editorial sidebar');
assertIncludes(css, '.ed-index-grid', 'CSS should style the GitHub beta dashboard index grid');
assertIncludes(css, '.ed-workflow', 'CSS should style the GitHub beta workflow columns');
assertIncludes(css, '.database-table', 'CSS should style the GitHub beta database table');
assertIncludes(css, 'min-width: 1180px', 'desktop database table should preserve dense legacy columns');
assertIncludes(css, '.database-table tbody tr:last-child td', 'database table should avoid trailing row borders');
assertIncludes(css, 'repeat(5, minmax(132px, 0.85fr))', 'database filters should allow the GitHub beta multi-filter bar');

console.log('next dashboard UI parity static checks passed');
