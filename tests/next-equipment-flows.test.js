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
  'src/app/equipment/page.tsx',
  'src/features/equipment/actions.ts',
  'src/features/equipment/queries.ts',
  'src/features/equipment/equipment-panel.tsx'
].forEach(assertFile);

const queries = read('src/features/equipment/queries.ts');
assertIncludes(queries, 'getEquipmentOverview', 'equipment queries should expose getEquipmentOverview');
assertIncludes(queries, 'from("cameras")', 'equipment overview should load user cameras');
assertIncludes(queries, 'from("lenses")', 'equipment overview should load user lenses');
assertIncludes(queries, 'from("rolls")', 'equipment overview should load roll references for safe delete/usage');
assertIncludes(queries, 'owner_user_id', 'equipment reads should stay scoped to the current owner');

const actions = read('src/features/equipment/actions.ts');
assertIncludes(actions, '"use server"', 'equipment mutations should run as Server Actions');
assertIncludes(actions, 'saveCameraAction', 'equipment flow should expose camera save mutation');
assertIncludes(actions, 'saveLensAction', 'equipment flow should expose lens save mutation');
assertIncludes(actions, 'removeCameraAction', 'equipment flow should expose camera remove mutation');
assertIncludes(actions, 'removeLensAction', 'equipment flow should expose lens remove mutation');
assertIncludes(actions, 'from("cameras")', 'camera mutations should use the cameras table');
assertIncludes(actions, 'from("lenses")', 'lens mutations should use the lenses table');
assertIncludes(actions, 'from("rolls")', 'remove actions should inspect roll references first');
assertIncludes(actions, '.delete()', 'unused equipment should be deletable');
assertIncludes(actions, 'show_in_quick_mode: false', 'referenced equipment should be hidden instead of breaking history');
assertIncludes(actions, 'revalidatePath("/equipment")', 'equipment mutations should invalidate equipment view');

const panel = read('src/features/equipment/equipment-panel.tsx');
assertIncludes(panel, 'Cámaras', 'equipment panel should render camera section');
assertIncludes(panel, 'Lentes', 'equipment panel should render lens section');
assertIncludes(panel, 'cam-catalog-grid', 'equipment panel should use the GitHub beta camera catalog grid');
assertIncludes(panel, 'cam-card', 'equipment panel should use GitHub beta camera cards');
assertIncludes(panel, 'cam-card-maker', 'equipment panel should render beta camera maker label');
assertIncludes(panel, 'cam-card-badges', 'equipment panel should render beta equipment badges');
assertIncludes(panel, 'cam-stats-label', 'equipment panel should render beta usage stats label');
assertIncludes(panel, 'cam-chart-wrap', 'equipment panel should render beta usage chart wrapper');
assertIncludes(panel, 'cam-modal-field', 'equipment forms should use beta modal field styling');
assertIncludes(panel, 'cam-modal-save', 'equipment forms should use beta modal save button styling');
assertIncludes(panel, 'name="maker"', 'equipment forms should capture maker');
assertIncludes(panel, 'name="model"', 'equipment forms should capture model');
assertIncludes(panel, 'name="mount"', 'equipment forms should capture mount');
assertIncludes(panel, 'name="showInQuickMode"', 'equipment forms should control quick-mode visibility');
assertIncludes(panel, 'name="supportsInterchangeableLenses"', 'camera forms should control integrated vs interchangeable lens bodies');
assertIncludes(panel, 'saveCameraAction', 'camera forms should submit through saveCameraAction');
assertIncludes(panel, 'saveLensAction', 'lens forms should submit through saveLensAction');
assertIncludes(panel, 'removeCameraAction', 'camera cards should expose remove/hide action');
assertIncludes(panel, 'removeLensAction', 'lens cards should expose remove/hide action');

const page = read('src/app/equipment/page.tsx');
assertIncludes(page, 'getCurrentAccessProfile', 'equipment route should use the same auth gate as protected routes');
assertIncludes(page, 'getEquipmentOverview', 'equipment route should load equipment overview data');
assertIncludes(page, '<AppShell active="equipment"', 'equipment route should use the shared GitHub beta approved shell');
assertIncludes(page, 'ed-page-header-kicker', 'equipment route should use the GitHub beta page header');
assertIncludes(page, 'PÁG·04', 'equipment route should match the GitHub beta page number');
assertIncludes(page, 'Tus cámaras,', 'equipment route should match the GitHub beta equipment title');
assertIncludes(page, '<EquipmentPanel', 'equipment route should render the equipment panel');

const appShell = read('src/features/navigation/app-shell.tsx');
assertIncludes(appShell, 'href: "/equipment"', 'approved shell should expose equipment management');

console.log('next equipment flow static checks passed');
