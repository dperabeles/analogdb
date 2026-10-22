-- ANA-173: índice para la llave foránea de la moneda predeterminada (aviso
-- unindexed_foreign_keys del asesor de Supabase).
create index finance_preferences_default_currency_idx
  on public.finance_preferences(default_currency);
