const assert = require('node:assert/strict');
const recovery = require('./auth-recovery.js');

assert.equal(
  recovery.buildForgotPasswordUrl('https://example.com/app/analog-db-dashboard.html'),
  'https://example.com/app/forgot-password.html'
);

assert.equal(
  recovery.buildRecoveryRedirectUrl('https://example.com/app/forgot-password.html'),
  'https://example.com/app/reset-password.html'
);

assert.equal(
  recovery.buildEntryUrl('https://example.com/app/reset-password.html'),
  'https://example.com/app/analog-db-dashboard.html'
);

assert.equal(recovery.validatePasswordReset('12345678', '12345678'), null);
assert.equal(
  recovery.validatePasswordReset('short', 'short'),
  'La nueva contraseña debe tener al menos 8 caracteres.'
);
assert.equal(
  recovery.validatePasswordReset('12345678', '87654321'),
  'La confirmación no coincide con la nueva contraseña.'
);

assert.equal(recovery.hasRecoveryParams({ search: '?code=abc', hash: '' }), true);
assert.equal(
  recovery.hasRecoveryParams({ search: '', hash: '#type=recovery&access' + '_token=token' }),
  true
);
assert.equal(recovery.hasRecoveryParams({ search: '', hash: '' }), false);

console.log('auth-recovery tests passed');
