const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'analog-db-dashboard.html'), 'utf8');
const migration = fs.readFileSync(
  path.join(root, 'supabase', 'migrations', '20260505_add_camera_lens_mounts.sql'),
  'utf8'
);

function expectIncludes(source, needle, message) {
  assert.ok(source.includes(needle), message || `Expected to find ${needle}`);
}

expectIncludes(migration, 'alter table public.cameras', 'migration should extend cameras');
expectIncludes(migration, 'add column if not exists mount text', 'cameras should get nullable mount');
expectIncludes(migration, 'add column if not exists supports_interchangeable_lenses boolean not null default true', 'cameras should track fixed-lens vs interchangeable-lens bodies');
expectIncludes(migration, 'create table if not exists public.lenses', 'migration should create lenses table');
expectIncludes(migration, 'maker text not null', 'lens maker should be required');
expectIncludes(migration, 'add column if not exists lens_id bigint', 'rolls should get nullable lens_id');
expectIncludes(migration, 'execute function public.touch_updated_at()', 'lenses should reuse the existing updated_at trigger helper');
expectIncludes(migration, "coalesce(nullif(trim(concat_ws(' ', l.maker, l.model)), ''), r.lens)", 'rolls_flat should preserve legacy LENS text with lens fallback');

expectIncludes(html, 'let LENSES_CATALOG = []', 'frontend should load a lens catalog');
expectIncludes(html, 'id="camInputMount"', 'camera form should expose mount');
expectIncludes(html, 'id="camInputInterchangeable"', 'camera form should expose interchangeable-lens control');
expectIncludes(html, 'cameraSupportsInterchangeableLenses', 'quick add should know whether a camera can select lenses');
expectIncludes(html, 'qaNextStepFromCamera', 'quick add should skip lens selection when camera has an integrated lens');
expectIncludes(html, 'renderEquipmentMobile', 'mobile account should expose equipment management');
expectIncludes(html, 'openEquipment', 'mobile account should navigate to cameras and lenses without changing bottom nav');
expectIncludes(html, '<div class="knum">Equipo</div>', 'mobile equipment header should say Equipo');
expectIncludes(html, '<div class="ksub">Catálogo del equipo</div>', 'mobile equipment subtitle should stay concise');
expectIncludes(html, 'mob-equipment-add-row', 'mobile equipment add action should live in the content area');
expectIncludes(html, 'mob-equipment-edit', 'mobile equipment edit action should be visually highlighted');
expectIncludes(html, 'cameraSchemaCacheMissing', 'camera save should handle preview DB schema-cache misses gracefully');
expectIncludes(html, 'qaLensesForCamera', 'quick add should filter lenses for a camera');
expectIncludes(html, 'cameraMountForLensFilter', 'lens filtering should use camera mount');
expectIncludes(html, 'window._qaShowAddCamera', 'quick add should expose add-camera flow');
expectIncludes(html, 'window._qaSaveNewCamera', 'quick add should save a new camera');
expectIncludes(html, 'window._qaShowAddLens', 'quick add should expose add-lens flow');
expectIncludes(html, 'window._qaSaveNewLens', 'quick add should save a new lens');
expectIncludes(html, 'qa-list-it qa-add-row', 'quick add CTAs should use the highlighted add-row treatment');
expectIncludes(html, "stepBar(5, 'Resumen')", 'quick add should have a dedicated summary step');
expectIncludes(html, "qaState.step === 5 ? 'Crear rollo' : 'Continuar'", 'quick add should create the roll from the summary step');
expectIncludes(html, 'qaSortCamerasByUsage', 'quick add should sort cameras by historical usage');
expectIncludes(html, 'qaSortLensesByUsage', 'quick add should sort lenses by historical usage');
expectIncludes(html, 'Agregar cámara', 'quick add should show add camera CTA');
expectIncludes(html, 'Agregar lente', 'quick add should show add lens CTA');

console.log('camera lens quick-add static checks passed');
