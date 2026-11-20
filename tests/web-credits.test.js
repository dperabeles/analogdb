const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// Diego, 20-nov: the credits of the camera catalogue go on the legal pages.
// CameraHub is Apache 2.0: its copyright notice and the licence travel with
// what we took. Wikidata is CC0; it is credited out of courtesy.

const root = path.join(__dirname, '..');
const read = (filePath) => fs.readFileSync(path.join(root, filePath), 'utf8');

const credits = read('src/content/legal/credits.md');
assert.ok(credits.includes('CameraHub'), 'CameraHub is credited');
assert.ok(credits.includes('Jonathan Gazeley'), 'with its copyright holder');
assert.ok(credits.includes('https://www.apache.org/licenses/LICENSE-2.0'), 'and the Apache 2.0 licence');
assert.ok(credits.includes('Wikidata'), 'Wikidata is credited');
assert.ok(/\*\*Última actualización:\*\*/.test(credits), 'it says when it changed, like the other legal pages');

assert.ok(fs.existsSync(path.join(root, 'src/app/(legal)/credits/page.tsx')), '/credits is a legal page');
assert.ok(read('src/features/legal/legal-content.ts').includes('credits: "credits.md"'), 'it reads its markdown');
assert.ok(read('next.config.js').includes('"/credits"'), 'and Vercel packs the markdown');

assert.ok(read('src/features/legal/legal-footer.tsx').includes('href="/credits"'), 'the legal footer links it');
assert.ok(read('src/features/landing/landing.tsx').includes('href="/credits"'), 'and so does the home page');

const paused = read('src/lib/webapp-paused.ts');
assert.ok(!paused.includes('"/credits"'), '/credits is not part of the paused web app');
