-- ════════════════════════════════════════════════════════════════
-- Migration: 20260526_mobile_support_and_auto_approve.sql
-- ════════════════════════════════════════════════════════════════
--
-- Cubre dos cambios para soporte de la app móvil (M1):
--
--   1. AAM-026: Cambio de default profiles.status a 'approved'.
--      Decisión 2026-05-26: TestFlight External será público y no
--      queremos aprobar manualmente cada signup. Esto requiere:
--        a. ALTER COLUMN DEFAULT en profiles.status
--        b. Actualizar el trigger handle_new_auth_user
--        c. Actualizar policy profiles_self_insert
--
--   2. AAM-003: Schema additions para mobile (FCM tokens, mobile version
--      tracking, terms acceptance, notification prefs, roll reminder tracking).
--
-- Aplicar a:
--   - Repo: github.com/dperabeles/analogdb (branch nuevo, NUNCA main)
--   - Path: supabase/migrations/20260526_mobile_support_and_auto_approve.sql
--   - Apply: supabase db push --linked
--
-- Backup pre-migración recomendado:
--   supabase db dump --linked --data-only > backup-pre-20260526.sql
-- (o usar el script de backup existente en analogdb-repo)
--
-- ════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- 1. AAM-026 · Auto-approve signups
-- ════════════════════════════════════════════════════════════════

-- 1a. Cambiar default de la columna (formal, aunque el trigger es lo crítico)
ALTER TABLE public.profiles ALTER COLUMN status SET DEFAULT 'approved';

COMMENT ON COLUMN public.profiles.status IS
  'User status: pending|approved|rejected. Default: approved (changed 2026-05-26 for TestFlight public launch). Admin can manually set to rejected for suspensions via admin_set_profile_status RPC.';

-- 1b. Actualizar el trigger para escribir 'approved' directamente.
--     Mantiene toda la lógica de display_name + user_roles del original.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  requested_display_name text;
BEGIN
  requested_display_name := btrim(coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  IF char_length(requested_display_name) < 3 THEN
    requested_display_name := btrim(split_part(coalesce(new.email, 'user'), '@', 1));
  END IF;

  IF char_length(requested_display_name) < 3 THEN
    requested_display_name := 'User';
  END IF;

  requested_display_name := left(requested_display_name, 20);

  INSERT INTO public.profiles (
    user_id,
    email,
    display_name,
    status,                     -- ← CAMBIO: 'approved' en lugar de 'pending'
    approved_at,                -- ← NUEVO: set automáticamente a now()
    approved_by,                -- ← null (auto-approved, no actor)
    rejected_at,
    rejected_by
  ) VALUES (
    new.id,
    new.email,
    requested_display_name,
    'approved',                 -- ← CAMBIO
    now(),                      -- ← NUEVO
    null,
    null,
    null
  )
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.user_roles (
    user_id,
    role,
    is_founder,
    granted_by
  ) VALUES (
    new.id,
    'user',
    false,
    null
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN new;
END;
$$;

-- 1c. Actualizar policy profiles_self_insert para alinear con el nuevo default.
--     Aunque el trigger usa SECURITY DEFINER y bypassa policies, mejor mantener
--     consistencia para evitar confusión futura.
DROP POLICY IF EXISTS profiles_self_insert ON public.profiles;
CREATE POLICY profiles_self_insert
ON public.profiles
FOR INSERT
TO public
WITH CHECK (
  user_id = auth.uid()
  AND email = auth.jwt() ->> 'email'
  AND status IN ('pending', 'approved')   -- ← CAMBIO: acepta ambos
  AND rejected_at IS NULL
  AND rejected_by IS NULL
);


-- ════════════════════════════════════════════════════════════════
-- 2. AAM-003 · Mobile support schema additions
-- ════════════════════════════════════════════════════════════════

-- 2a. FCM tokens (push notifications)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fcm_token text,
  ADD COLUMN IF NOT EXISTS fcm_platform text CHECK (fcm_platform IN ('ios','android')),
  ADD COLUMN IF NOT EXISTS fcm_token_updated_at timestamptz;

COMMENT ON COLUMN public.profiles.fcm_token IS
  'Firebase Cloud Messaging token. Used by send-push-notif Edge Function. Updated on app launch and on token refresh.';

-- 2b. Mobile version tracking (para forzar updates si rompemos compatibilidad)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_mobile_version text,
  ADD COLUMN IF NOT EXISTS last_mobile_seen_at timestamptz;

-- 2c. Terms acceptance tracking (para re-aceptar cuando cambien materialmente)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_terms_accepted_version text,
  ADD COLUMN IF NOT EXISTS last_terms_accepted_at timestamptz;

-- 2d. Notification preferences (jsonb default opt-in)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notification_prefs jsonb DEFAULT '{
    "account_status": true,
    "roll_reminders": true,
    "legal_updates": true
  }'::jsonb;

COMMENT ON COLUMN public.profiles.notification_prefs IS
  'Notification preferences per user. Schema: {account_status, roll_reminders, legal_updates}: bool. Default opt-in. legal_updates always sent if fcm_token present (compliance).';

-- 2e. Roll reminder tracking (para cron de overdue notifs)
ALTER TABLE public.rolls
  ADD COLUMN IF NOT EXISTS marked_to_develop_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_reminder_sent_at timestamptz;

COMMENT ON COLUMN public.rolls.marked_to_develop_at IS
  'Timestamp when status was set to to_develop. Auto-managed by trigger. Used by check-overdue-rolls cron.';

-- 2f. Trigger: auto-set marked_to_develop_at
--     ⚠️ DIFERIDO A M2: necesitamos saber los valores exactos de rolls.status
--     que el schema actual usa (es text libre, sin check constraint).
--     En M2 cuando definamos el enum RollStatus en Flutter y mapeemos a los
--     valores reales del DB, agregaremos este trigger con valores correctos.
--
--     Por ahora, la columna marked_to_develop_at queda nullable y será
--     backfilled manualmente cuando la lógica esté clara, o set por el
--     mutation desde la app móvil cuando el usuario marque el roll.

-- 2g. RLS policy: usuario puede actualizar su propio fcm_token (UPDATE específico)
--     Las policies actuales de profiles no incluyen UPDATE para self; agregamos una
--     restringida solo a actualizar columnas mobile (fcm_token, prefs, etc.).
--
--     IMPORTANTE: necesitamos GRANT UPDATE en profiles (las grants actuales solo son
--     select, insert).
GRANT UPDATE (
  fcm_token, fcm_platform, fcm_token_updated_at,
  last_mobile_version, last_mobile_seen_at,
  last_terms_accepted_version, last_terms_accepted_at,
  notification_prefs
) ON public.profiles TO authenticated;

DROP POLICY IF EXISTS profiles_self_update_mobile ON public.profiles;
CREATE POLICY profiles_self_update_mobile
ON public.profiles
FOR UPDATE
TO public
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 2h. Push log table (para AAM-035 send-push-notif logging futuro)
CREATE TABLE IF NOT EXISTS public.push_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(user_id) ON DELETE CASCADE,
  type text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  deeplink text,
  status text NOT NULL CHECK (status IN ('sent', 'failed', 'opted_out')),
  fcm_response_code int,
  created_at timestamptz DEFAULT now()
);

-- Solo service_role puede leer/escribir push_log (logs internos para auditoría)
ALTER TABLE public.push_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_log FROM anon, authenticated;
GRANT ALL ON public.push_log TO service_role;

CREATE INDEX IF NOT EXISTS push_log_user_id_created_at_idx
  ON public.push_log (user_id, created_at DESC);


-- ════════════════════════════════════════════════════════════════
-- 3. Verificaciones post-migración
-- ════════════════════════════════════════════════════════════════
--
-- Ejecutar manualmente en Supabase SQL editor después del push:
--
--   -- Verificar default
--   SELECT column_default FROM information_schema.columns
--   WHERE table_name = 'profiles' AND column_name = 'status';
--   -- Expected: 'approved'::text
--
--   -- Verificar columnas nuevas
--   SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name = 'profiles' AND column_name LIKE 'fcm%';
--   -- Expected: fcm_token (text), fcm_platform (text), fcm_token_updated_at (timestamptz)
--
--   -- Verificar trigger handle_new_auth_user actualizado
--   SELECT prosrc FROM pg_proc WHERE proname = 'handle_new_auth_user';
--   -- Expected: ver "'approved'" en el body
--
--   -- Verificar policy profiles_self_update_mobile
--   SELECT polname FROM pg_policy
--   WHERE polrelid = 'public.profiles'::regclass
--     AND polname = 'profiles_self_update_mobile';
--   -- Expected: 1 row
--
--   -- Verificar push_log table existe + RLS
--   SELECT relname, relrowsecurity FROM pg_class
--   WHERE relname = 'push_log';
--   -- Expected: push_log, t
--
-- ════════════════════════════════════════════════════════════════
