const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// Every dependency names one exact version: a deploy never picks up a new
// release without a commit that says so (ANA-191). "latest", ^ and ~ let
// Vercel install something no one tested.
const root = path.join(__dirname, '..');
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));

for (const section of ['dependencies', 'devDependencies']) {
  for (const [name, spec] of Object.entries(pkg[section] || {})) {
    assert.match(spec, /^\d+\.\d+\.\d+$/, `${name} must be an exact version, not "${spec}"`);
    const locked = lock.packages[`node_modules/${name}`];
    assert.ok(locked, `${name} is missing from package-lock.json`);
    assert.equal(locked.version, spec, `${name}: package.json and package-lock.json disagree`);
    const rootSection = lock.packages['']?.[section] ?? {};
    assert.equal(rootSection[name], spec, `${name}: the lockfile root ${section} still says something else`);
  }
}

console.log('dependency pinning checks passed');
