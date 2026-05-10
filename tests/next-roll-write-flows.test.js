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
  'src/features/rolls/actions.ts',
  'src/features/rolls/roll-form.tsx',
  'src/app/rolls/new/page.tsx',
  'src/app/rolls/[code]/edit/page.tsx'
].forEach(assertFile);

const actions = read('src/features/rolls/actions.ts');
assertIncludes(actions, '"use server"', 'roll mutations should run as Server Actions');
assertIncludes(actions, 'saveRollAction', 'roll write flow should expose saveRollAction');
assertIncludes(actions, 'deleteRollAction', 'roll write flow should expose deleteRollAction');
assertIncludes(actions, 'from("film_stocks")', 'saving a roll should upsert film stocks like the legacy UI');
assertIncludes(actions, 'from("cameras")', 'saving a roll should upsert cameras like the legacy UI');
assertIncludes(actions, 'from("labs")', 'saving a roll should upsert labs like the legacy UI');
assertIncludes(actions, 'from("rolls")', 'saving a roll should write the normalized rolls table');
assertIncludes(actions, 'onConflict: "owner_user_id,code"', 'new rolls should preserve the legacy owner/code upsert contract');
assertIncludes(actions, 'owner_user_id: profile.userId', 'writes should be scoped to the approved user');
assertIncludes(actions, 'revalidatePath("/dashboard")', 'saving should invalidate the dashboard read view');

const form = read('src/features/rolls/roll-form.tsx');
[
  'name="code"',
  'name="filmStock"',
  'name="manufacturer"',
  'name="filmType"',
  'name="format"',
  'name="maker"',
  'name="modelName"',
  'name="lens"',
  'name="locations"',
  'name="photoType"',
  'name="tags"',
  'name="status"',
  'name="rating"',
  'name="notes"'
].forEach((needle) => assertIncludes(form, needle, `roll form should include ${needle}`));
assertIncludes(form, 'action={saveRollAction}', 'roll form should submit through the Server Action');

const newPage = read('src/app/rolls/new/page.tsx');
assertIncludes(newPage, '<RollForm', 'new roll route should render the roll form');

const editPage = read('src/app/rolls/[code]/edit/page.tsx');
assertIncludes(editPage, 'getRollByCode', 'edit route should load the current roll');
assertIncludes(editPage, '<RollForm', 'edit route should render the roll form with the current roll');

const dashboard = read('src/app/dashboard/page.tsx');
assertIncludes(dashboard, 'href="/rolls/new"', 'dashboard should expose a create-roll entry point');

const detail = read('src/features/rolls/roll-detail.tsx');
assertIncludes(detail, '/edit', 'roll detail should link to edit route');
assertIncludes(detail, 'deleteRollAction', 'roll detail should expose delete action for the current roll');

const database = read('src/types/database.ts');
assertIncludes(database, 'film_stocks', 'Database type should include film_stocks for write flows');
assertIncludes(database, 'labs', 'Database type should include labs for write flows');
assertIncludes(database, 'film_stock_id', 'rolls type should include normalized write fields');

console.log('next roll write flow static checks passed');
