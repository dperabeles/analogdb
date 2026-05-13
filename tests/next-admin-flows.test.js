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
  'src/app/admin/page.tsx',
  'src/features/admin/actions.ts',
  'src/features/admin/queries.ts',
  'src/features/admin/admin-panel.tsx'
].forEach(assertFile);

const queries = read('src/features/admin/queries.ts');
assertIncludes(queries, 'getAdminOverview', 'admin queries should expose getAdminOverview');
assertIncludes(queries, 'from("profiles")', 'admin overview should load profiles');
assertIncludes(queries, '.eq("status", "pending")', 'admin overview should load pending users');
assertIncludes(queries, '.eq("status", "approved")', 'admin overview should load approved users');
assertIncludes(queries, '.eq("status", "rejected")', 'admin overview should load rejected users');
assertIncludes(queries, 'from("user_roles")', 'admin overview should load admin roster');
assertIncludes(queries, 'from("admin_actions")', 'admin overview should load admin action queue');

const actions = read('src/features/admin/actions.ts');
assertIncludes(actions, '"use server"', 'admin mutations should run as Server Actions');
assertIncludes(actions, 'setProfileStatusAction', 'admin flow should expose profile status mutation');
assertIncludes(actions, 'requestAdminRoleChangeAction', 'admin flow should expose role-change request mutation');
assertIncludes(actions, 'voteAdminAction', 'admin flow should expose admin vote mutation');
assertIncludes(actions, 'admin_set_profile_status', 'status changes should use the legacy RPC');
assertIncludes(actions, 'request_admin_action', 'role changes should use the legacy RPC');
assertIncludes(actions, 'cast_admin_action_vote', 'votes should use the legacy RPC');
assertIncludes(actions, 'revalidatePath("/admin")', 'admin mutations should invalidate the admin view');

const panel = read('src/features/admin/admin-panel.tsx');
assertIncludes(panel, 'Pending', 'admin panel should render pending users');
assertIncludes(panel, 'Aprobados', 'admin panel should render approved users');
assertIncludes(panel, 'Usuarios rechazados', 'admin panel should render rejected users');
assertIncludes(panel, 'Acciones admin', 'admin panel should render admin action queue');
assertIncludes(panel, 'name="status"', 'profile status forms should submit the target status');
assertIncludes(panel, 'status="approved"', 'pending users should be approvable');
assertIncludes(panel, 'status="rejected"', 'pending users should be rejectable');
assert.match(
  panel,
  /function RejectedUsers[\s\S]*status="approved"/,
  'rejected users should be reactivatable to approved'
);
assertIncludes(panel, 'promote_to_admin', 'approved users should support admin promotion requests');
assertIncludes(panel, 'demote_from_admin', 'admin users should support downgrade requests');

const page = read('src/app/admin/page.tsx');
assertIncludes(page, 'getCurrentAccessProfile', 'admin route should use the same auth gate as other protected routes');
assertIncludes(page, 'getAdminOverview', 'admin route should load admin overview data');
assertIncludes(page, '<AdminPanel', 'admin route should render the admin panel');

const dashboard = read('src/app/dashboard/page.tsx');
assertIncludes(dashboard, 'href="/admin"', 'dashboard should expose the admin route to admins');

const database = read('src/types/database.ts');
assertIncludes(database, 'user_roles', 'Database type should include admin roles');
assertIncludes(database, 'admin_actions', 'Database type should include admin action queue');
assertIncludes(database, 'admin_set_profile_status', 'Database type should include admin status RPC');

console.log('next admin flow static checks passed');
