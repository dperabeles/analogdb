-- ============================================================
-- ANA-62 · Modo offline O2 — identidad idempotente de rolls
-- Aplicada a producción: 2026-07-06 vía `supabase db query --linked`
-- (historial de migraciones desincronizado; no usar db push).
--
-- `client_uuid` lo genera el cliente (uuid v4) en TODO insert de rolls.
-- El índice único parcial hace el sync del outbox idempotente: un reintento
-- tras crash choca en 23505 → la app recupera el id existente en vez de
-- duplicar el film. NULL permitido → las 149 filas históricas intactas.
--
-- Validación previa: select count(*) from public.rolls → 149.
-- Verificación post: pg_indexes contiene rolls_client_uuid_key;
-- information_schema.columns contiene rolls.client_uuid.
-- ============================================================

alter table public.rolls add column if not exists client_uuid uuid;

create unique index if not exists rolls_client_uuid_key
  on public.rolls (client_uuid) where client_uuid is not null;
