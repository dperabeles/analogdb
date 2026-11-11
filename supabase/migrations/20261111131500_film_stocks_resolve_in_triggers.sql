-- The triggers that check the film of a roll or of a favourite ran as the
-- writing user, and app_private.resolve_film_stock is executable only by
-- postgres: a plain insert of a roll failed with "permission denied for
-- function resolve_film_stock". Both triggers become security definer.
--
-- They resolve with the writing account (auth.uid()), and with the row's
-- owner only when there is no signed-in session. Resolving with the
-- row's owner for a signed-in writer would tell an account whether an id is
-- another account's private film (the trigger runs before RLS rejects the
-- foreign owner).

create or replace function app_private.rolls_film_visible()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  if new.film_stock_id is not null then
    v_id := app_private.resolve_film_stock(new.film_stock_id, coalesce(auth.uid(), new.owner_user_id));
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
      v_id := app_private.resolve_film_stock(new.favorite_film_stock_id, coalesce(auth.uid(), new.user_id));
      if v_id is null then
        raise exception 'Favorite film must be visible to profile owner' using errcode = '23514';
      end if;
      new.favorite_film_stock_id := v_id;
    end if;
  end if;
  return new;
end
$$;

-- Trigger functions are never called directly; firing a trigger does not
-- check EXECUTE.
revoke all on function app_private.rolls_film_visible() from public, anon, authenticated;
revoke all on function public.validate_profile_favorites() from public, anon, authenticated;
