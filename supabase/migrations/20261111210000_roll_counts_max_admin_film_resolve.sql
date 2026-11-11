-- A roll holds at most 100 frames, as the phone (kMaxFrames) and the web form
-- (MAX_FRAMES): a typo like 360 exposures is refused. The archive's largest
-- is 41.
--
-- The triggers that check the film of a roll or a favourite resolve with the
-- writing account so a signed-in user cannot probe another account's
-- private films. An admin writing another account's row (a review, support)
-- is trusted, and resolves with the row's owner, like a write without a
-- session: otherwise moving a user's roll to that user's own private film
-- was refused.
alter table public.rolls
  add constraint rolls_exp_count_max check (exp_count is null or exp_count <= 100),
  add constraint rolls_exp_taken_max check (exp_taken is null or exp_taken <= 100);

create or replace function app_private.rolls_film_visible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_as uuid := auth.uid();
begin
  if new.film_stock_id is not null then
    if v_as is null or public.app_is_admin(v_as) then
      v_as := new.owner_user_id;
    end if;
    v_id := app_private.resolve_film_stock(new.film_stock_id, v_as);
    if v_id is null then
      raise exception 'Film stock not available' using errcode = '23514';
    end if;
    new.film_stock_id := v_id;
  end if;
  return new;
end;
$$;

create or replace function public.validate_profile_favorites()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_as uuid := auth.uid();
begin
  if new.favorite_camera_id is not null and not exists (
    select 1 from public.cameras c
    where c.id = new.favorite_camera_id and c.owner_user_id = new.user_id
  ) then
    raise exception 'Favorite camera must belong to profile owner' using errcode = '23514';
  end if;
  if new.favorite_lens_id is not null and not exists (
    select 1 from public.lenses l
    where l.id = new.favorite_lens_id and l.owner_user_id = new.user_id
  ) then
    raise exception 'Favorite lens must belong to profile owner' using errcode = '23514';
  end if;
  -- Checked when it is set or changed, so an old favourite never blocks
  -- saving the rest of the profile.
  if new.favorite_film_stock_id is not null then
    if tg_op = 'INSERT'
       or new.favorite_film_stock_id is distinct from old.favorite_film_stock_id then
      if v_as is null or public.app_is_admin(v_as) then
        v_as := new.user_id;
      end if;
      v_id := app_private.resolve_film_stock(new.favorite_film_stock_id, v_as);
      if v_id is null then
        raise exception 'Favorite film must be visible to profile owner' using errcode = '23514';
      end if;
      new.favorite_film_stock_id := v_id;
    end if;
  end if;
  return new;
end
$$;

revoke all on function app_private.rolls_film_visible() from public, anon, authenticated;
revoke all on function public.validate_profile_favorites() from public, anon, authenticated;
