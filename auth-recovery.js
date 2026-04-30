(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.AnalogAuthRecovery = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  const SUPABASE_URL = 'https://dqjjxxqruxxfsfoejdzl.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_t8qzsNZaeCwAIbpEIoBPTQ_wF_30652';
  const ENTRY_PAGE = 'analog-db-dashboard.html';
  const FORGOT_PAGE = 'forgot-password.html';
  const RESET_PAGE = 'reset-password.html';
  const MIN_PASSWORD_LENGTH = 8;

  function toUrl(input) {
    return new URL(input, 'http://localhost');
  }

  function buildSiblingUrl(currentHref, filename) {
    const url = toUrl(currentHref);
    const path = url.pathname;
    const basePath = path.endsWith('/') ? path : path.replace(/[^/]*$/, '');
    return new URL(filename, url.origin + basePath).toString();
  }

  function buildEntryUrl(currentHref) {
    return buildSiblingUrl(currentHref, ENTRY_PAGE);
  }

  function buildForgotPasswordUrl(currentHref) {
    return buildSiblingUrl(currentHref, FORGOT_PAGE);
  }

  function buildRecoveryRedirectUrl(currentHref) {
    return buildSiblingUrl(currentHref, RESET_PAGE);
  }

  function createSupabaseClient() {
    if (!globalThis.supabase?.createClient) {
      throw new Error('Supabase client is not available on this page.');
    }
    return globalThis.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
  }

  function getNeutralRecoveryMessage() {
    return 'Si el correo existe en Analogdb, te enviamos un enlace para restablecer tu contraseña.';
  }

  function getRateLimitMessage() {
    return 'No pudimos enviar el correo en este momento. Intenta de nuevo en unos minutos.';
  }

  function getInvalidRecoveryMessage() {
    return 'El enlace de recuperación es inválido o expiró. Solicita uno nuevo para continuar.';
  }

  function getSuccessPasswordResetMessage() {
    return 'Tu contraseña fue actualizada. Ya puedes volver a iniciar sesión.';
  }

  function readParamsFromLocation(loc) {
    const hash = new URLSearchParams(String(loc.hash || '').replace(/^#/, ''));
    const search = new URLSearchParams(String(loc.search || ''));
    return { hash, search };
  }

  function hasRecoveryParams(loc) {
    const { hash, search } = readParamsFromLocation(loc);
    return (
      hash.get('type') === 'recovery' ||
      search.get('type') === 'recovery' ||
      hash.has('access' + '_token') ||
      search.has('code') ||
      search.has('token_hash')
    );
  }

  function validatePasswordReset(password, confirmPassword) {
    if (!password || password.length < MIN_PASSWORD_LENGTH) {
      return 'La nueva contraseña debe tener al menos 8 caracteres.';
    }
    if (password !== confirmPassword) {
      return 'La confirmación no coincide con la nueva contraseña.';
    }
    return null;
  }

  function extractErrorMessage(error, fallback) {
    const msg = String(error?.message || '').trim();
    return msg || fallback;
  }

  return {
    SUPABASE_URL,
    SUPABASE_KEY,
    ENTRY_PAGE,
    FORGOT_PAGE,
    RESET_PAGE,
    MIN_PASSWORD_LENGTH,
    buildEntryUrl,
    buildForgotPasswordUrl,
    buildRecoveryRedirectUrl,
    createSupabaseClient,
    getNeutralRecoveryMessage,
    getRateLimitMessage,
    getInvalidRecoveryMessage,
    getSuccessPasswordResetMessage,
    hasRecoveryParams,
    validatePasswordReset,
    extractErrorMessage,
  };
});
