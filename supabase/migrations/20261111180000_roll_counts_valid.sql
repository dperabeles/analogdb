-- A roll's counts are whole numbers that make sense: exposures and push ISO
-- at least 1, frames shot (the +1/-1 count) at least 0, a film's ISO at least
-- 1. A roll was saved with -2 exposures from the web on 2026-11-11; the form
-- now refuses it, and this keeps any client from storing it again.
alter table public.rolls
  add constraint rolls_exp_count_positive check (exp_count is null or exp_count >= 1),
  add constraint rolls_exp_taken_not_negative check (exp_taken is null or exp_taken >= 0),
  add constraint rolls_iso_pushed_positive check (iso_pushed is null or iso_pushed >= 1);

alter table public.film_stocks
  add constraint film_stocks_iso_positive check (iso is null or iso >= 1);
