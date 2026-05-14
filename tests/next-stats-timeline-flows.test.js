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
  'src/app/stats/page.tsx',
  'src/app/timeline/page.tsx',
  'src/features/analytics/queries.ts',
  'src/features/analytics/stats-panel.tsx',
  'src/features/analytics/timeline-panel.tsx'
].forEach(assertFile);

const queries = read('src/features/analytics/queries.ts');
assertIncludes(queries, 'getAnalyticsOverview', 'analytics queries should expose getAnalyticsOverview');
assertIncludes(queries, 'getRolls', 'analytics should reuse the shared roll read flow');
assertIncludes(queries, 'filmTypeCounts', 'analytics should compute film type counts');
assertIncludes(queries, 'formatCounts', 'analytics should compute format counts');
assertIncludes(queries, 'stockLeaders', 'analytics should compute stock leaders');
assertIncludes(queries, 'labLeaders', 'analytics should compute lab leaders');
assertIncludes(queries, 'cameraLeaders', 'analytics should compute camera leaders');
assertIncludes(queries, 'locationLeaders', 'analytics should compute location leaders');
assertIncludes(queries, 'tagLeaders', 'analytics should compute tag leaders');
assertIncludes(queries, 'timelineGroups', 'analytics should group rolls for timeline');

const statsPanel = read('src/features/analytics/stats-panel.tsx');
assertIncludes(statsPanel, 'Tipo de rollo', 'stats panel should render film type section');
assertIncludes(statsPanel, 'Formatos', 'stats panel should render format section');
assertIncludes(statsPanel, 'Stocks favoritos', 'stats panel should render stock leaders');
assertIncludes(statsPanel, 'Laboratorios', 'stats panel should render lab leaders');
assertIncludes(statsPanel, 'Camaras', 'stats panel should render camera leaders');
assertIncludes(statsPanel, 'Ubicaciones', 'stats panel should render location leaders');
assertIncludes(statsPanel, 'Tags', 'stats panel should render tag leaders');

const timelinePanel = read('src/features/analytics/timeline-panel.tsx');
assertIncludes(timelinePanel, 'timelineGroups', 'timeline panel should render grouped roll data');
assertIncludes(timelinePanel, 'Sin fecha', 'timeline panel should support undated rolls');
assertIncludes(timelinePanel, 'href={`/rolls/${encodeURIComponent(roll.code)}`}', 'timeline rows should link to roll detail');

const statsPage = read('src/app/stats/page.tsx');
assertIncludes(statsPage, 'getCurrentAccessProfile', 'stats route should use protected auth gate');
assertIncludes(statsPage, 'getAnalyticsOverview', 'stats route should load analytics data');
assertIncludes(statsPage, '<AppShell active="stats"', 'stats route should use the shared GitHub beta approved shell');
assertIncludes(statsPage, 'ed-page-header-kicker', 'stats route should use the GitHub beta page header');
assertIncludes(statsPage, 'PÁG·05', 'stats route should match the GitHub beta page number');
assertIncludes(statsPage, '<StatsPanel', 'stats route should render stats panel');

const timelinePage = read('src/app/timeline/page.tsx');
assertIncludes(timelinePage, 'getCurrentAccessProfile', 'timeline route should use protected auth gate');
assertIncludes(timelinePage, 'getAnalyticsOverview', 'timeline route should load analytics data');
assertIncludes(timelinePage, '<AppShell active="timeline"', 'timeline route should use the shared GitHub beta approved shell');
assertIncludes(timelinePage, 'ed-page-header-kicker', 'timeline route should use the GitHub beta page header');
assertIncludes(timelinePage, 'PÁG·03', 'timeline route should match the GitHub beta page number');
assertIncludes(timelinePage, '<TimelinePanel', 'timeline route should render timeline panel');

const appShell = read('src/features/navigation/app-shell.tsx');
assertIncludes(appShell, 'href: "/stats"', 'approved shell should expose stats route');
assertIncludes(appShell, 'href: "/timeline"', 'approved shell should expose timeline route');

console.log('next stats/timeline flow static checks passed');
