-- ============================================================
-- AAM Fase 2 — Endurecimiento aditivo (code review de la app móvil)
-- Aplicada a producción: 2026-07-06 vía `supabase db query --linked`
-- (el historial de migraciones estaba desincronizado; no usar db push).
--
-- Validación previa ejecutada (solo lectura):
--   select coalesce(status,'(NULL)'), count(*) from public.rolls group by 1;
--   → 149 rolls, únicamente los 5 valores esperados, sin NULLs.
--
-- Todo es aditivo: no modifica ni borra datos. Idempotente (re-ejecutable).
-- ============================================================

-- 1) CHECK en rolls.status — la columna era texto libre; ambos clientes
--    (web roll-types.ts y móvil RollStatus) escriben solo estos 5 valores.
--    NULL sigue permitido (semántica de IN con NULL).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'rolls_status_allowed'
  ) then
    alter table public.rolls
      add constraint rolls_status_allowed check (
        status in ('In Camera', 'To Develop', 'In Development', 'Developed', 'Archived')
      );
  end if;
end $$;

-- 2) cameras: timestamps + trigger touch_updated_at (espejo de lenses;
--    rolls/roll_exposures/lenses ya lo tenían, cameras no).
alter table public.cameras
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

drop trigger if exists cameras_touch on public.cameras;
create trigger cameras_touch
before update on public.cameras
for each row
execute function public.touch_updated_at();
