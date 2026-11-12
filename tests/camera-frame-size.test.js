const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

// ANA-135: a camera is 120 and its frame size (6x4.5, 6x6, 6x7, 6x9) is a
// detail of the camera, not a format of its own.
const root = path.join(__dirname, '..');

function load(relativePath) {
  const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const sandbox = { exports: {}, require, module: { exports: {} } };
  sandbox.exports = sandbox.module.exports;
  vm.runInNewContext(compiled, sandbox);
  return sandbox.module.exports;
}

const { CAMERA_FRAME_SIZES, cameraFrameSize } = load('src/features/equipment/frame-size.ts');

assert.deepEqual([...CAMERA_FRAME_SIZES], ['6x4.5', '6x6', '6x7', '6x8', '6x9', '6x12', '6x17']);
assert.equal(cameraFrameSize('120', '6x4.5'), '6x4.5');
assert.equal(cameraFrameSize('120', '6x9'), '6x9');
assert.equal(cameraFrameSize('120', '6x17'), '6x17', 'panoramic 120');
assert.equal(cameraFrameSize('120', ''), null, 'no size chosen');
assert.equal(cameraFrameSize('120', null), null);
assert.equal(cameraFrameSize('120', '4x5'), null, 'only the 120 sizes');
assert.equal(cameraFrameSize('35mm', '6x6'), null, 'only a 120 camera has one');
assert.equal(cameraFrameSize(null, '6x6'), null);

const panel = fs.readFileSync(path.join(root, 'src/features/equipment/equipment-panel.tsx'), 'utf8');
const formatSelect = panel.slice(panel.indexOf('name="format"'), panel.indexOf('</select>', panel.indexOf('name="format"')));
for (const size of ['6x4.5', '6x6', '6x7', '6x8', '6x9', '6x12', '6x17']) {
  assert.ok(!formatSelect.includes(`value="${size}"`), `${size} is no longer a format`);
}
assert.ok(panel.includes('name="frameSize"'), 'the camera form picks the frame size');
assert.ok(panel.includes('Tamaño negativo'), 'the field is called «Tamaño negativo»');
assert.ok(panel.includes('camera.frame_size'), 'the camera card shows the frame size');

const actions = fs.readFileSync(path.join(root, 'src/features/equipment/actions.ts'), 'utf8');
assert.ok(actions.includes('frame_size: cameraFrameSize('), 'saving a camera stores the size through cameraFrameSize');

console.log('camera frame size checks passed');
