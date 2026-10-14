-- Private identity. No public profile lookup, email resolver or mutable owner.
-- Existing preferences/annual goals and the signup/profile trigger stay intact.
create schema app_private;
revoke all on schema app_private from public, anon;
create role analog_profile_identity_executor nologin noinherit nobypassrls;
grant analog_profile_identity_executor to postgres;
grant usage, create on schema app_private to analog_profile_identity_executor;
grant usage on schema public to analog_profile_identity_executor;
grant usage on schema app_private to authenticated, supabase_auth_admin;

create table app_private.identity_policy (
  singleton boolean primary key default true check (singleton),
  require_username_for_signup boolean not null default false
);
insert into app_private.identity_policy values (true, false);

create table app_private.username_claims (
  username text primary key check (
    char_length(username) between 3 and 24 and
    username ~ '^[a-z0-9]+([._][a-z0-9]+)*$'
  ),
  state text not null check (state in ('active','held','reserved','blocked')),
  owner_user_id uuid references auth.users(id) on delete set null,
  reserved_for_user_id uuid references auth.users(id) on delete set null,
  held_until timestamptz,
  check (
    (state = 'active' and owner_user_id is not null and held_until is null and
      (reserved_for_user_id is null or reserved_for_user_id = owner_user_id)) or
    (state = 'held' and owner_user_id is null and held_until is not null and reserved_for_user_id is null) or
    (state = 'reserved' and owner_user_id is null and held_until is null) or
    (state = 'blocked' and owner_user_id is null and held_until is null and reserved_for_user_id is null)
  )
);
create unique index username_one_active_per_owner on app_private.username_claims(owner_user_id)
  where state = 'active';
create index username_expired_holds on app_private.username_claims(held_until)
  where state = 'held';
insert into app_private.username_claims(username,state) values
  ('dperabeles','reserved'), ('diegoperabeles','blocked');
-- The verified beneficiary is assigned by the operator, not a client claim.
-- A deleted beneficiary leaves the permanent reservation unavailable.

create table app_private.profile_identities (
  user_id uuid primary key references public.profiles(user_id) on delete cascade,
  username text references app_private.username_claims(username) deferrable initially deferred,
  revision bigint not null default 1 check (revision > 0),
  username_changed_at timestamptz,
  check (username is not null or username_changed_at is null)
);

alter table app_private.identity_policy enable row level security;
alter table app_private.username_claims enable row level security;
alter table app_private.profile_identities enable row level security;
revoke all on all tables in schema app_private from public, anon, authenticated;
grant select on app_private.identity_policy to analog_profile_identity_executor, supabase_auth_admin;
grant select, insert, update, delete on app_private.username_claims, app_private.profile_identities
  to analog_profile_identity_executor;
grant select on app_private.username_claims to supabase_auth_admin;
create policy identity_executor_policy on app_private.identity_policy for select
  to analog_profile_identity_executor using (true);
create policy identity_auth_policy on app_private.identity_policy for select
  to supabase_auth_admin using (true);
create policy claims_executor_policy on app_private.username_claims
  to analog_profile_identity_executor using (true) with check (true);
create policy claims_auth_read on app_private.username_claims for select
  to supabase_auth_admin using (true);
create policy identities_executor_policy on app_private.profile_identities
  to analog_profile_identity_executor using (true) with check (true);

-- Supabase's managed auth schema does not grant USAGE/lock grant-options to
-- new roles. Two bounded, unexposed postgres-owned helpers below inspect only
-- the verified request's uid/session. The writer never inherits authenticated,
-- service_role or Auth-admin permissions, and has no Auth table privileges.
create function app_private.current_request_user()
returns uuid language sql stable security definer set search_path = '' as $$
  select auth.uid()
$$;
grant select(user_id,display_name,status), update(user_id) on public.profiles to analog_profile_identity_executor;
-- Existing PUBLIC policies evaluate this helper even when an own-row policy
-- also admits the row. Its boolean result never changes the RPC's uid filter.
grant execute on function public.app_is_admin(uuid) to analog_profile_identity_executor;
grant select, insert on public.profile_preferences to analog_profile_identity_executor;
grant update(bio,favorite_film_stock_id,favorite_camera_id,favorite_lens_id)
  on public.profile_preferences to analog_profile_identity_executor;
grant select(id), update(id) on public.film_stocks to analog_profile_identity_executor;
grant select(id,owner_user_id), update(id) on public.cameras, public.lenses to analog_profile_identity_executor;
create policy identity_read_profile on public.profiles for select
  to analog_profile_identity_executor using (user_id = (select app_private.current_request_user()));
create policy identity_lock_profile on public.profiles for update
  to analog_profile_identity_executor using (user_id = (select app_private.current_request_user())) with check (user_id = (select app_private.current_request_user()));
create policy identity_read_preferences on public.profile_preferences for select
  to analog_profile_identity_executor using (user_id = (select app_private.current_request_user()));
create policy identity_insert_preferences on public.profile_preferences for insert
  to analog_profile_identity_executor with check (user_id = (select app_private.current_request_user()));
create policy identity_update_preferences on public.profile_preferences for update
  to analog_profile_identity_executor using (user_id = (select app_private.current_request_user())) with check (user_id = (select app_private.current_request_user()));
create policy identity_read_stock on public.film_stocks for select
  to analog_profile_identity_executor using (true);
create policy identity_lock_stock on public.film_stocks for update
  to analog_profile_identity_executor using (true) with check (true);
create policy identity_read_camera on public.cameras for select
  to analog_profile_identity_executor using (owner_user_id = (select app_private.current_request_user()));
create policy identity_lock_camera on public.cameras for update
  to analog_profile_identity_executor using (owner_user_id = (select app_private.current_request_user())) with check (owner_user_id = (select app_private.current_request_user()));
create policy identity_read_lens on public.lenses for select
  to analog_profile_identity_executor using (owner_user_id = (select app_private.current_request_user()));
create policy identity_lock_lens on public.lenses for update
  to analog_profile_identity_executor using (owner_user_id = (select app_private.current_request_user())) with check (owner_user_id = (select app_private.current_request_user()));

create function app_private.normalize_username(candidate text)
returns text language plpgsql immutable set search_path = '' as $$
declare v text;
begin
  -- Unicode White_Space plus BOM matches client trim, but only ASCII folds.
  v := btrim(candidate, E' \t\n\r\v\f' || U&'\0085\00a0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200a\2028\2029\202f\205f\3000\feff');
  if left(v,1) = '@' then v := substr(v,2); end if;
  return translate(v,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz');
end $$;

create function app_private.valid_username(candidate text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(char_length(candidate) between 3 and 24 and
    candidate ~ '^[a-z0-9]+([._][a-z0-9]+)*$', false)
$$;

create function app_private.check_identity_links()
returns trigger language plpgsql security definer set search_path = '' as $$
declare uid uuid; candidate uuid[];
begin
  candidate := array[
    (to_jsonb(new)->>'user_id')::uuid, (to_jsonb(old)->>'user_id')::uuid,
    (to_jsonb(new)->>'owner_user_id')::uuid, (to_jsonb(old)->>'owner_user_id')::uuid
  ];
  foreach uid in array candidate loop
    if uid is null then continue; end if;
    if exists (
      select 1 from app_private.profile_identities i
      where i.user_id=uid and i.username is not null and not exists (
        select 1 from app_private.username_claims c
        where c.username=i.username and c.state='active' and c.owner_user_id=i.user_id
      )
    ) or exists (
      select 1 from app_private.username_claims c where c.owner_user_id=uid and c.state='active'
      and not exists (select 1 from app_private.profile_identities i
        where i.user_id=uid and i.username=c.username)
    ) then
      raise exception 'Identity and active username must match' using errcode='23514';
    end if;
  end loop;
  return null;
end $$;
create constraint trigger identity_matches_claim after insert or update or delete
  on app_private.profile_identities deferrable initially deferred
  for each row execute function app_private.check_identity_links();
create constraint trigger claim_matches_identity after insert or update or delete
  on app_private.username_claims deferrable initially deferred
  for each row execute function app_private.check_identity_links();

create function app_private.require_identity_session(lock_rows boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); sid uuid;
begin
  begin sid := (auth.jwt()->>'session_id')::uuid;
  exception when invalid_text_representation then sid := null; end;
  if uid is null or sid is null then
    raise exception 'Profile session invalid' using errcode='P1006';
  end if;
  if lock_rows then
    perform id from auth.users where id=uid for key share;
    if not found then raise exception 'Profile session invalid' using errcode='P1006'; end if;
    perform id from auth.sessions where id=sid and user_id=uid
      and (not_after is null or not_after > clock_timestamp()) for share;
  else
    perform s.id from auth.sessions s join auth.users u on u.id=s.user_id
      where s.id=sid and s.user_id=uid and (s.not_after is null or s.not_after > clock_timestamp());
  end if;
  if not found then raise exception 'Profile session invalid' using errcode='P1006'; end if;
  return uid;
end $$;

create function app_private.read_profile_edit()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid; result jsonb;
begin
  uid := app_private.require_identity_session(false);
  -- ONE SELECT: two separately valid snapshots cannot become a mixed baseline.
  select jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,
    'identity',jsonb_build_object('username',i.username,'revision',coalesce(i.revision::text,'0'),
      'username_changed_at',i.username_changed_at,
      'username_change_available_at',case when i.username_changed_at + interval '720 hours' > clock_timestamp()
        then i.username_changed_at + interval '720 hours' else null end),
    'preferences',case when f.user_id is null then null else jsonb_build_object(
      'user_id',f.user_id,'alias',f.alias,'bio',f.bio,
      'favorite_film_stock_id',f.favorite_film_stock_id,'favorite_camera_id',f.favorite_camera_id,
      'favorite_lens_id',f.favorite_lens_id,'updated_at',f.updated_at) end)
  into result from public.profiles p
    left join app_private.profile_identities i on i.user_id=p.user_id
    left join public.profile_preferences f on f.user_id=p.user_id where p.user_id=uid;
  if result is null then raise exception 'Profile session invalid' using errcode='P1006'; end if;
  return result;
end $$;

-- Never called directly by authenticated/anon. The only callers pass either
-- auth.uid() after session validation or NEW.id from the trusted Auth trigger.
create function app_private.claim_username(uid uuid, candidate text, old_name text, at_time timestamptz)
returns void language plpgsql set search_path = '' as $$
declare key text; target app_private.username_claims%rowtype;
begin
  if not app_private.valid_username(candidate) then
    raise exception 'Username invalid' using errcode='P1001';
  end if;
  for key in select distinct value collate "C" as value from unnest(array[candidate,old_name]) value
    where value is not null order by value loop
    perform pg_advisory_xact_lock(hashtextextended('analog.username:'||key,0));
  end loop;
  select * into target from app_private.username_claims where username=candidate for update;
  if found and not coalesce((
    (target.state='held' and target.held_until <= at_time) or
    (target.state='reserved' and target.reserved_for_user_id=uid)
  ),false) then
    raise exception 'Username unavailable' using errcode='P1002';
  end if;
  if old_name is not null then
    update app_private.username_claims set
      state=case when reserved_for_user_id is not null then 'reserved' else 'held' end,
      owner_user_id=null,
      held_until=case when reserved_for_user_id is not null then null else at_time+interval '720 hours' end
    where username=old_name and state='active' and owner_user_id=uid;
    if not found then raise exception 'Identity changed' using errcode='P1004'; end if;
  end if;
  insert into app_private.username_claims(username,state,owner_user_id)
    values(candidate,'active',uid)
    on conflict(username) do update set state='active',owner_user_id=excluded.owner_user_id,held_until=null;
end $$;

create function app_private.save_profile_edit(
  p_change_username boolean, p_username_candidate text, p_bio text,
  p_favorite_film_stock_id bigint, p_favorite_camera_id bigint, p_favorite_lens_id bigint,
  p_expected_identity_revision text, p_expected_preferences_updated_at timestamptz
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid; old_identity app_private.profile_identities%rowtype;
  old_prefs public.profile_preferences%rowtype; candidate text; normalized_bio text;
  changed boolean; at_time timestamptz;
begin
  uid := app_private.require_identity_session(true);
  perform user_id from public.profiles where user_id=uid for update;
  if not found then raise exception 'Profile session invalid' using errcode='P1006'; end if;
  select * into old_identity from app_private.profile_identities where user_id=uid for update;
  if p_expected_identity_revision is distinct from coalesce(old_identity.revision::text,'0') then
    raise exception 'Identity changed' using errcode='P1004';
  end if;
  if p_change_username is null then raise exception 'Username invalid' using errcode='P1001'; end if;
  candidate := case when p_change_username then app_private.normalize_username(p_username_candidate)
    else old_identity.username end;
  if p_change_username and not app_private.valid_username(candidate) then
    raise exception 'Username invalid' using errcode='P1001';
  end if;
  changed := p_change_username and candidate is distinct from old_identity.username;
  at_time := clock_timestamp();
  if changed and old_identity.username_changed_at + interval '720 hours' > at_time then
    raise exception 'Username change not yet available' using errcode='P1003';
  end if;
  -- Name changes are transactional: any invalid favorite/version below also
  -- reverts the name claim. Key-share before prefs avoids gear-delete inversion.
  if changed then
    perform app_private.claim_username(uid,candidate,old_identity.username,at_time);
  end if;
  if p_favorite_film_stock_id is not null then
    perform id from public.film_stocks where id=p_favorite_film_stock_id for key share;
    if not found or p_favorite_film_stock_id <= 0 then raise exception 'Favorite invalid' using errcode='P1005'; end if;
  end if;
  if p_favorite_camera_id is not null then
    perform id from public.cameras where id=p_favorite_camera_id and owner_user_id=uid for key share;
    if not found or p_favorite_camera_id <= 0 then raise exception 'Favorite invalid' using errcode='P1005'; end if;
  end if;
  if p_favorite_lens_id is not null then
    perform id from public.lenses where id=p_favorite_lens_id and owner_user_id=uid for key share;
    if not found or p_favorite_lens_id <= 0 then raise exception 'Favorite invalid' using errcode='P1005'; end if;
  end if;
  select * into old_prefs from public.profile_preferences where user_id=uid for update;
  if old_prefs.updated_at is distinct from p_expected_preferences_updated_at then
    raise exception 'Preferences changed' using errcode='P1004';
  end if;
  normalized_bio := nullif(btrim(p_bio),'');
  if char_length(normalized_bio)>160 then raise exception 'Profile text invalid' using errcode='P1001'; end if;
  if changed then
    insert into app_private.profile_identities(user_id,username,revision,username_changed_at)
      values(uid,candidate,1,null)
      on conflict(user_id) do update set username=excluded.username,
        revision=app_private.profile_identities.revision+1,
        username_changed_at=case when app_private.profile_identities.username is null
          then null else at_time end;
  end if;
  insert into public.profile_preferences(user_id,bio,favorite_film_stock_id,favorite_camera_id,favorite_lens_id)
    values(uid,normalized_bio,p_favorite_film_stock_id,p_favorite_camera_id,p_favorite_lens_id)
    on conflict(user_id) do update set bio=excluded.bio,favorite_film_stock_id=excluded.favorite_film_stock_id,
      favorite_camera_id=excluded.favorite_camera_id,favorite_lens_id=excluded.favorite_lens_id;
  return app_private.read_profile_edit();
end $$;

create function app_private.signup_identity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare candidate text; required_name boolean;
begin
  select require_username_for_signup into required_name from app_private.identity_policy where singleton;
  if required_name is null then raise exception 'Identity policy unavailable'; end if;
  candidate := app_private.normalize_username(new.raw_user_meta_data->>'username');
  if candidate is null or candidate='' then
    if required_name then raise exception 'Username required' using errcode='P1001'; end if;
    return new;
  end if;
  perform app_private.claim_username(new.id,candidate,null,clock_timestamp());
  insert into app_private.profile_identities(user_id,username) values(new.id,candidate);
  return new;
end $$;
-- Alphabetic trigger order preserves the current profile/role initialization.
create trigger zz_auth_user_claim_username after insert on auth.users
  for each row execute function app_private.signup_identity();

create function app_private.release_deleted_identity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare old_name text;
begin
  select username into old_name from app_private.profile_identities where user_id=old.id for update;
  if old_name is not null then
    perform pg_advisory_xact_lock(hashtextextended('analog.username:'||old_name,0));
    update app_private.username_claims set
      state=case when reserved_for_user_id is not null then 'reserved' else 'held' end,
      owner_user_id=null,
      held_until=case when reserved_for_user_id is not null then null else clock_timestamp()+interval '720 hours' end
      where username=old_name and owner_user_id=old.id and state='active';
  end if;
  return old;
end $$;
create trigger release_username_before_auth_delete before delete on auth.users
  for each row execute function app_private.release_deleted_identity();

create function app_private.cleanup_username_holds()
returns integer language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  -- No account link remains in a hold. Recheck state/deadline after waiting on
  -- row locks; a concurrent claim changes state and cannot be removed here.
  with expired as (select username from app_private.username_claims
    where state='held' and held_until<=clock_timestamp() order by held_until limit 500 for update skip locked)
  delete from app_private.username_claims c using expired e
    where c.username=e.username and c.state='held' and c.held_until<=clock_timestamp();
  get diagnostics n = row_count;
  return n;
end $$;

create function public.read_my_profile_edit_state()
returns jsonb language sql security invoker set search_path = '' as $$
  select app_private.read_profile_edit()
$$;
create function public.save_my_profile_edit(
  p_change_username boolean, p_username_candidate text, p_bio text,
  p_favorite_film_stock_id bigint, p_favorite_camera_id bigint, p_favorite_lens_id bigint,
  p_expected_identity_revision text, p_expected_preferences_updated_at timestamptz
) returns jsonb language sql security invoker set search_path = '' as $$
  select app_private.save_profile_edit(p_change_username,p_username_candidate,p_bio,
    p_favorite_film_stock_id,p_favorite_camera_id,p_favorite_lens_id,
    p_expected_identity_revision,p_expected_preferences_updated_at)
$$;

create function public.before_user_created_username(event jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare candidate text; required_name boolean; uid uuid; target app_private.username_claims%rowtype;
begin
  select require_username_for_signup into required_name from app_private.identity_policy where singleton;
  if required_name is null then raise exception 'Identity policy unavailable'; end if;
  candidate := app_private.normalize_username(event->'user'->'user_metadata'->>'username');
  if (candidate is null or candidate='') and not required_name then return '{}'::jsonb; end if;
  if not app_private.valid_username(candidate) then
    return jsonb_build_object('error',jsonb_build_object('http_code',400,'message','[username_invalid] Elige un nombre de usuario válido.'));
  end if;
  uid := (event->'user'->>'id')::uuid;
  select * into target from app_private.username_claims where username=candidate;
  if found and not coalesce((
    (target.state='held' and target.held_until<=clock_timestamp()) or
    (target.state='reserved' and target.reserved_for_user_id=uid)
  ),false) then
    return jsonb_build_object('error',jsonb_build_object('http_code',400,'message','[username_unavailable] Ese nombre de usuario no está disponible.'));
  end if;
  return '{}'::jsonb;
end $$;

alter function app_private.normalize_username(text) owner to analog_profile_identity_executor;
alter function app_private.valid_username(text) owner to analog_profile_identity_executor;
alter function app_private.check_identity_links() owner to analog_profile_identity_executor;
alter function app_private.read_profile_edit() owner to analog_profile_identity_executor;
alter function app_private.claim_username(uuid,text,text,timestamptz) owner to analog_profile_identity_executor;
alter function app_private.save_profile_edit(boolean,text,text,bigint,bigint,bigint,text,timestamptz) owner to analog_profile_identity_executor;
alter function app_private.signup_identity() owner to analog_profile_identity_executor;
alter function app_private.release_deleted_identity() owner to analog_profile_identity_executor;
alter function app_private.cleanup_username_holds() owner to analog_profile_identity_executor;
revoke create on schema app_private from analog_profile_identity_executor;
revoke all on all functions in schema app_private from public, anon, authenticated, supabase_auth_admin;
grant execute on function app_private.current_request_user(), app_private.require_identity_session(boolean)
  to analog_profile_identity_executor;
grant execute on function app_private.read_profile_edit(),
  app_private.save_profile_edit(boolean,text,text,bigint,bigint,bigint,text,timestamptz) to authenticated;
grant execute on function app_private.normalize_username(text), app_private.valid_username(text) to supabase_auth_admin;
revoke all on function public.read_my_profile_edit_state(),
  public.save_my_profile_edit(boolean,text,text,bigint,bigint,bigint,text,timestamptz),
  public.before_user_created_username(jsonb) from public, anon, authenticated;
grant execute on function public.read_my_profile_edit_state(),
  public.save_my_profile_edit(boolean,text,text,bigint,bigint,bigint,text,timestamptz) to authenticated;
grant execute on function public.before_user_created_username(jsonb) to supabase_auth_admin;

comment on table app_private.username_claims is 'Private namespace. Held names retain only name and deadline, never previous owner.';
comment on function public.before_user_created_username(jsonb) is 'Read-only preflight; Auth trigger and PK remain the transactional authority.';
create extension if not exists pg_cron;
select cron.schedule('profile_username_cleanup', '0 * * * *', 'select app_private.cleanup_username_holds();');
notify pgrst, 'reload schema';
