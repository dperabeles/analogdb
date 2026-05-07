const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname, '..', 'analog-db-dashboard.html'), 'utf8');

function expectIncludes(needle, message) {
  assert.ok(html.includes(needle), message || `Expected HTML to include ${needle}`);
}

function expectNotIncludes(needle, message) {
  assert.ok(!html.includes(needle), message || `Expected HTML not to include ${needle}`);
}

expectIncludes("show_in_quick_mode: true", 'seed cameras should default to quick-mode visibility');
expectIncludes("id=\"camInputQuickMode\"", 'camera form should expose the quick-mode visibility checkbox');
expectIncludes("formatCompatibleForQuickMode", 'quick-mode camera filtering should compare camera and roll formats');
expectIncludes("quickModeCamerasForRoll", 'quick-mode camera filtering helper should exist');
expectIncludes("cameraQuickModeVisible", 'quick-mode camera filtering should exclude hidden cameras');
expectIncludes(".filter(c => quickModeCamerasForRoll(rec['FORMAT']).includes(c))", 'roll editor model list should be filtered by roll format and quick-mode visibility');
expectIncludes("selectedRollFormatForCameraFilter()", 'model refresh should use the currently selected roll format');
expectIncludes("persistCameraRemoteCompat(payload, editingCameraId)", 'editing a camera should persist format, mount, lens mode, and quick-mode visibility');
expectIncludes("persistCameraRemoteCompat(payload, null)", 'creating a camera should persist mount, lens mode, and quick-mode visibility');
expectIncludes("show_in_quick_mode|supports_interchangeable_lenses", 'camera preview fallback should catch missing quick-mode and interchangeable columns');
expectIncludes("white-space: nowrap;", 'quick-add step labels should stay on one line');
expectIncludes("n + ' ' + label", 'quick-add step labels should use compact mobile copy');
expectNotIncludes("'0' + n + ' · ' + label", 'quick-add step labels should not use padded numbers and separators');

console.log('camera quick-mode static checks passed');
