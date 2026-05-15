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
  'src/features/rolls/queries.ts',
  'src/features/rolls/roll-types.ts',
  'src/features/rolls/roll-list.tsx',
  'src/features/rolls/roll-filters.tsx',
  'src/features/rolls/roll-detail.tsx',
  'src/app/rolls/[code]/page.tsx'
].forEach(assertFile);

const queries = read('src/features/rolls/queries.ts');
assertIncludes(queries, 'from("rolls_flat")', 'roll read flows should use the backward-compatible Supabase view');
assertIncludes(queries, '.order("id", { ascending: false })', 'default roll ordering should match the GitHub Pages id.desc query');
assertIncludes(queries, 'getRollByCode', 'detail route should fetch a single roll by legacy roll code');

const rollTypes = read('src/features/rolls/roll-types.ts');
assertIncludes(rollTypes, 'normalizePushPull', 'rolls_flat rows should normalize PUSH/PULL like the legacy UI');
assertIncludes(rollTypes, 'normalizeFormatValue', 'rolls_flat rows should normalize FORMAT like the legacy UI');

const list = read('src/features/rolls/roll-list.tsx');
assertIncludes(list, 'filterRolls', 'roll list should apply filters before rendering');
assertIncludes(list, 'sortRolls', 'roll list should support deterministic sort modes');
assertIncludes(list, 'encodeURIComponent(roll.code)', 'roll cards should link safely to detail routes');

const filters = read('src/features/rolls/roll-filters.tsx');
assertIncludes(filters, 'name="status"', 'filters should expose status filtering');
assertIncludes(filters, 'name="q"', 'filters should expose text search');
assertIncludes(filters, 'name="sort"', 'filters should expose sort selection');

const dashboard = read('src/app/dashboard/page.tsx');
assertIncludes(dashboard, 'getRolls()', 'approved dashboard should read rolls from Supabase');
assertIncludes(dashboard, '<DashboardOverview', 'approved dashboard should render the GitHub-style workflow roll overview');

const dashboardOverview = read('src/features/rolls/dashboard-overview.tsx');
assertIncludes(dashboardOverview, 'encodeURIComponent(roll.code)', 'dashboard workflow cards should link safely to detail routes');

const detailPage = read('src/app/rolls/[code]/page.tsx');
assertIncludes(detailPage, 'decodeURIComponent', 'detail page should decode URL roll codes');
assertIncludes(detailPage, '<AppShell active="detail"', 'detail page should use the shared GitHub beta approved shell');
assertIncludes(detailPage, '<RollDetail', 'detail page should render roll detail component');

const detail = read('src/features/rolls/roll-detail.tsx');
assertIncludes(detail, 'ed-modal-grid', 'roll detail should use GitHub beta modal detail grid');
assertIncludes(detail, 'ed-modal-section', 'roll detail should use GitHub beta modal sections');
assertIncludes(detail, 'ed-modal-row', 'roll detail should use GitHub beta modal rows');
assertIncludes(detail, 'ed-cronologia', 'roll detail should render GitHub beta chronology block');
assertIncludes(detail, 'ed-modal-actions', 'roll detail should use GitHub beta modal actions');

const database = read('src/types/database.ts');
assertIncludes(database, 'rolls_flat', 'Database type should include the rolls_flat view contract');
assertIncludes(database, '"FILM STOCK"', 'rolls_flat type should preserve legacy column names');

console.log('next roll read flow static checks passed');
