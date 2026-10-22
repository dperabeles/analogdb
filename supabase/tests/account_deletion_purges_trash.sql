-- Closing an account leaves nothing of it in the trash (deleted_rows): not the
-- rows the closure removes, and not the copies archived earlier, when the
-- person deleted rows the usual way. Privacy policy 5 promises the purge.
-- Run inside BEGIN / ROLLBACK, also immediately after applying the migration.
-- Synthetic accounts only (@trash.invalid).
alter table public.profiles disable trigger profiles_notify_approved;
alter table public.profiles disable trigger profiles_notify_pending_signup;
do $$
declare
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid();
  who uuid;
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data,
                          raw_app_meta_data, created_at, updated_at, email_confirmed_at)
  select v, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         t || '@trash.invalid', jsonb_build_object('username', 'trash_' || t),
         '{}'::jsonb, now(), now(), now()
  from (values (a, 'a'), (b, 'b'), (c, 'c')) as x(v, t);

  -- Each one deletes a roll the usual way, so it lands in the trash.
  foreach who in array array[a, b, c] loop
    insert into public.rolls (owner_user_id, code, client_uuid, status)
    values (who, 'R990', gen_random_uuid(), 'Developed');
    perform set_config('request.jwt.claims', json_build_object('sub', who, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', who::text, true);
    execute 'set local role authenticated';
    delete from public.rolls where owner_user_id = who;
    execute 'reset role';
    assert (select count(*) from public.deleted_rows where dueno = who and tabla = 'rolls') = 1,
           'a deleted roll is archived';
  end loop;

  -- A closes the account from the app.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', a::text, true);
  execute 'set local role authenticated';
  perform public.delete_my_account();
  execute 'reset role';
  assert not exists (select 1 from public.deleted_rows where dueno = a), 'closing the account empties its trash';
  assert exists (select 1 from public.deleted_rows where dueno = b), 'other accounts keep their trash';

  -- C is deleted another way (Supabase dashboard): its trash goes too.
  perform set_config('app.borrando_cuenta', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from auth.users where id = c;
  assert not exists (select 1 from public.deleted_rows where dueno = c), 'any account deletion empties its trash';
  assert (select count(*) from public.deleted_rows where dueno = b) = 1, 'B trash untouched';
end $$;
