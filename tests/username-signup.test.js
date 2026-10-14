const assert = require('node:assert/strict');
const { test } = require('node:test');
const { buildSignupRequest } = require('../src/features/auth/signup-identity.ts');

function signupForm(overrides = {}) {
  const form = new FormData();
  for (const [key, value] of Object.entries({
    displayName: '  Diego Perabeles  ',
    username: '  @Diego.P_13  ',
    email: '  photographer@example.test  ',
    password: ' a password with spaces ',
    ...overrides
  })) {
    if (value !== null) form.set(key, value);
  }
  return form;
}

// Catches dropping username metadata, deriving display_name from username,
// trimming passwords, or leaving the pasted handle unnormalized.
test('signup sends the canonical username alongside existing credentials and display name', () => {
  assert.deepEqual(buildSignupRequest(signupForm()), {
    ok: true,
    request: {
      email: 'photographer@example.test',
      password: ' a password with spaces ',
      options: { data: { display_name: 'Diego Perabeles', username: 'diego.p_13' } }
    }
  });
});

for (const [candidate, canonical] of [
  ['ABC', 'abc'],
  ['abc', 'abc'],
  ['ABCDEFGHIJKLMNOPQRSTUVWX', 'abcdefghijklmnopqrstuvwx'],
  ['a.1_b', 'a.1_b'],
  [' @Diego_13 ', 'diego_13'],
  ['dperabeles', 'dperabeles'],
  ['diegoperabeles', 'diegoperabeles']
]) {
  // Format validity must not pretend the server has granted availability.
  test(`signup accepts syntactically valid ${JSON.stringify(candidate)}`, () => {
    const result = buildSignupRequest(signupForm({ username: candidate }));
    assert.equal(result.ok, true);
    assert.equal(result.request.options.data.username, canonical);
  });
}

for (const candidate of [
  null, '', '   ', '@', 'ab', 'abcdefghijklmnopqrstuvwxy',
  '_diego', '.diego', 'diego_', 'diego.', 'diego..p', 'diego__p',
  'diego._p', 'diego_.p', 'die go', 'die\tgo', 'die\ngo',
  '@@diego', 'die@go', 'diégo', 'diegο', 'Kelvin', 'İiego', 'diego-p'
]) {
  // Catches omitted length/ASCII/separator guards, removing multiple @,
  // or Unicode case folding that accidentally accepts lookalike characters.
  test(`signup rejects malformed or missing username ${JSON.stringify(candidate)}`, () => {
    const result = buildSignupRequest(signupForm({ username: candidate }));
    assert.equal(result.ok, false);
    assert.equal(typeof result.error, 'string');
    assert.equal('request' in result, false);
  });
}

for (const displayName of ['', '  xy  ', 'abcdefghijklmnopqrstu']) {
  // Catches dropping the established display_name validation during signup.
  test(`signup still requires a valid display name ${JSON.stringify(displayName)}`, () => {
    const result = buildSignupRequest(signupForm({ displayName }));
    assert.equal(result.ok, false);
    assert.equal('request' in result, false);
  });
}

test('signup builds a request without changing the form draft', () => {
  const form = signupForm();
  const before = [...form.entries()];
  buildSignupRequest(form);
  assert.deepEqual([...form.entries()], before);
});
