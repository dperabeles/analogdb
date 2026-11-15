const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const routeDir = 'src/app/.well-known/apple-app-site-association';

function read(filePath) {
  return fs.readFileSync(path.join(root, filePath), 'utf8');
}

// ANA-69: analog-archive.com/app/* abre la app de iPhone. Solo /app: los
// correos de acceso (/confirm, /reset-password) siguen abriendo la web.
const aasa = JSON.parse(read(`${routeDir}/aasa.json`));

assert.deepEqual(Object.keys(aasa), ['applinks'], 'solo enlaces universales, nada de webcredentials ni appclips');
assert.equal(aasa.applinks.details.length, 1);

const [detail] = aasa.applinks.details;
assert.deepEqual(detail.appIDs, ['3487WMAVUP.com.analogarchive.analogArchive'], 'Team ID + bundle de la app real');
assert.deepEqual(detail.components, [{ '/': '/app/*', comment: 'Paginas de la app (ANA-71)' }]);

const json = JSON.stringify(aasa);
for (const authPath of ['/confirm', '/reset-password', '/forgot-password', '/dashboard']) {
  assert.ok(!json.includes(authPath), `${authPath} no debe abrir la app`);
}

const route = read(`${routeDir}/route.ts`);
assert.ok(route.includes('application/json'), 'Apple exige Content-Type application/json');
assert.ok(route.includes('force-static'), 'el archivo es estático: sin sesión ni cookies');

const middleware = read('middleware.ts');
assert.ok(middleware.includes('\\\\.well-known'), 'el middleware no debe tocar /.well-known');
