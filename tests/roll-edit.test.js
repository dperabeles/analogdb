const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const root = path.join(__dirname, '..');

function load(relativePath) {
  const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020
    }
  }).outputText;
  const sandbox = { exports: {}, require, module: { exports: {} } };
  sandbox.exports = sandbox.module.exports;
  vm.runInNewContext(compiled, sandbox);
  return sandbox.module.exports;
}

const { mapRollFlatRow } = load('src/features/rolls/roll-types.ts');
const {
  ROLL_FORM_FIELDS,
  changedRollFields,
  formatOptionValue,
  formatStorageValue,
  parseOriginalValues,
  planRollUpdate,
  readRollForm,
  rollFormDefaults,
  selectOptions
} = load('src/features/rolls/roll-edit.ts');

// A roll as production stores most of them: 35mm, push "0", no rating, a
// catalogue lens and a lab. Saving it untouched on the web used to erase the
// format, turn push "0" into null, rating null into 0 and drop the lens link.
const roll = mapRollFlatRow({
  '#': 'R042',
  id: 42,
  'FILM STOCK': 'HP5 Plus',
  MANUFACTURER: 'Ilford',
  'FILM TYPE': 'B/W',
  FORMAT: 35,
  'EXP/FRESH': 'FRESH',
  ISO: 400,
  EXP: 36,
  MAKER: 'Nikon',
  'MODEL NAME': 'F3',
  'C. FORMAT': '35mm',
  'C. TYPE': 'SLR',
  'C. MOUNT': 'Nikon F',
  LENS: 'Nikon 50mm f/1.4',
  'LENS MOUNT': 'Nikon F',
  LOCATIONS: 'Monterrey, CDMX',
  'PHOTO TYPE': 'Street',
  TAGS: null,
  'ISO @': null,
  STARTED: '2026-09-01',
  FINISHED: null,
  '# EXP': 36,
  'PUSH/PULL': '0',
  DEV: 'Lab Uno',
  SCAN: 'Lab Uno',
  STATUS: 'Archived',
  RATING: null,
  NOTES: 'Primera línea\nSegunda línea',
  'FRAME SETTINGS': 0
});

// Values built inside the vm context have their own Array/Object prototypes,
// so deepEqual would fail on identical contents. Compare plain copies.
function plain(value) {
  return JSON.parse(JSON.stringify(value));
}

function formLike(values) {
  return { get: (name) => (name in values ? values[name] : null) };
}

const defaults = rollFormDefaults(roll);

// The form shows what the select can represent, not the display label.
assert.equal(defaults.format, '35', '35mm shows as the "35" option');
assert.equal(defaults.pushPull, '', 'push "0" shows as an empty field');
assert.equal(defaults.rating, '', 'no rating shows as an empty field');
assert.equal(formatOptionValue('8'), 'Super8');
assert.equal(formatOptionValue('120'), '120');
assert.equal(formatOptionValue('16'), '16mm');
assert.equal(formatOptionValue('45'), 'Large Format');
assert.equal(formatOptionValue('127'), '127', 'an unknown format is kept as is');
assert.equal(formatOptionValue(null), '');
for (const option of ['35', '120', 'Super8', '110', '16mm', 'Large Format']) {
  assert.equal(formatOptionValue(String(formatStorageValue(option))), option, `${option} round-trips`);
}
assert.deepEqual(plain(selectOptions(['35', '120'], '127')), ['35', '120', '127'], 'a value the select lacks is offered');
assert.deepEqual(plain(selectOptions(['35', '120'], '35')), ['35', '120']);
assert.deepEqual(plain(selectOptions(['35', '120'], '')), ['35', '120']);

// Untouched: the browser sends back exactly what the form showed, except that
// a textarea sends CRLF line breaks.
const untouched = readRollForm(formLike({ ...defaults, notes: defaults.notes.replace(/\n/g, '\r\n') }));
assert.deepEqual(plain(changedRollFields(defaults, untouched)), [], 'nothing changed');
const untouchedPlan = planRollUpdate([], untouched);
assert.deepEqual(plain(untouchedPlan.row), {}, 'an untouched roll writes no column');
assert.equal(untouchedPlan.film || untouchedPlan.camera || untouchedPlan.dev || untouchedPlan.scan, false,
  'an untouched roll resolves no film, camera or lab');

// Surrounding spaces are not a change: the action trims them.
assert.deepEqual(plain(changedRollFields(defaults, { ...defaults, lens: '  Nikon 50mm f/1.4 ' })), []);

// Changing only the notes writes only the notes.
const notesOnly = { ...defaults, notes: 'Nueva nota\r\notra' };
assert.deepEqual(plain(changedRollFields(defaults, notesOnly)), ['notes']);
assert.deepEqual(plain(planRollUpdate(['notes'], notesOnly).row), { notes: 'Nueva nota\notra' });

// Changing the lens text is the only case that replaces the link with text.
const lensChanged = { ...defaults, lens: 'Voigtländer 40mm f/1.4' };
assert.deepEqual(plain(changedRollFields(defaults, lensChanged)), ['lens']);
assert.deepEqual(plain(planRollUpdate(['lens'], lensChanged).row), { lens_id: null, lens: 'Voigtländer 40mm f/1.4' });

// Format, push and rating map like the old action did, but only when edited.
assert.deepEqual(plain(planRollUpdate(['format'], { ...defaults, format: 'Super8' }).row), { format: 8 });
assert.deepEqual(plain(planRollUpdate(['format'], { ...defaults, format: '' }).row), { format: null });
assert.deepEqual(plain(planRollUpdate(['pushPull'], { ...defaults, pushPull: '+1' }).row), { push_pull: '+1' });
assert.deepEqual(plain(planRollUpdate(['rating'], { ...defaults, rating: '4' }).row), { rating: 4 });
assert.deepEqual(plain(planRollUpdate(['locations'], { ...defaults, locations: 'Monterrey, Saltillo' }).row),
  { locations: ['Monterrey', 'Saltillo'] });

// References are resolved only when their own text changed.
const filmPlan = planRollUpdate(['iso'], { ...defaults, iso: '800' });
assert.equal(filmPlan.film, true);
assert.equal(filmPlan.camera, false);
assert.deepEqual(plain(filmPlan.row), {});

const cameraPlan = planRollUpdate(['modelName'], { ...defaults, modelName: 'FM2' });
assert.equal(cameraPlan.camera, true);
assert.deepEqual(plain(cameraPlan.cameraDetails), {},
  'switching camera does not copy the old camera format, type or mount onto the new one');
const mountPlan = planRollUpdate(['cameraMount'], { ...defaults, cameraMount: 'Nikon F (AI)' });
assert.deepEqual(plain(mountPlan.cameraDetails), { mount: 'Nikon F (AI)' }, 'only the edited camera detail is written');

const labPlan = planRollUpdate(['scan'], { ...defaults, scan: 'Lab Dos' });
assert.equal(labPlan.scan, true);
assert.equal(labPlan.dev, false, 'the developing lab keeps its branch');

assert.throws(() => planRollUpdate(['code'], { ...defaults, code: '   ' }), /code is required/);

// The original values travel with the form. Anything malformed is rejected so
// the action falls back to reading the roll instead of guessing.
assert.deepEqual(plain(parseOriginalValues(JSON.stringify(defaults))), plain(defaults));
assert.equal(parseOriginalValues(null), null);
assert.equal(parseOriginalValues('no es json'), null);
assert.equal(parseOriginalValues(JSON.stringify({ code: 'R042' })), null, 'missing fields');
assert.equal(parseOriginalValues(JSON.stringify({ ...defaults, rating: 4 })), null, 'non-string value');

// Every field the form submits is covered.
assert.deepEqual([...ROLL_FORM_FIELDS].sort(), Object.keys(defaults).sort());

console.log('roll edit checks passed');
