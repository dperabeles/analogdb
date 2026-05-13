const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'src/features/rolls/roll-types.ts'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020
  }
}).outputText;

const sandbox = {
  exports: {},
  require,
  module: { exports: {} }
};
sandbox.exports = sandbox.module.exports;
vm.runInNewContext(compiled, sandbox);

const { mapRollFlatRow, normalizeFormatValue } = sandbox.module.exports;

assert.equal(normalizeFormatValue(35), '35mm');
assert.equal(normalizeFormatValue(120), '120');
assert.equal(normalizeFormatValue(8), '8');

const roll = mapRollFlatRow({
  '#': 'R001',
  id: 1,
  FORMAT: 35,
  STATUS: 'In Camera',
  'PUSH/PULL': null,
  'FRAME SETTINGS': null
});

assert.equal(roll.format, '35mm');

console.log('roll format normalization checks passed');
