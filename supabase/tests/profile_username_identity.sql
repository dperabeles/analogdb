-- Run inside BEGIN / ROLLBACK, also immediately after applying the migration.
-- All people/equipment here are synthetic and this script returns no secrets.
do $$
#variable_conflict use_column
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
  sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid(); camera bigint; foreign_camera bigint;
  state jsonb; saved jsonb; stamp timestamptz; changed timestamptz;
begin
  assert app_private.normalize_username(E' \t@Diego.P\n')='diego.p', 'canonical ASCII normalization';
  assert not app_private.valid_username(app_private.normalize_username('Kelvin')), 'Unicode lookalike rejected';
  assert not app_private.valid_username(app_private.normalize_username('@@diego')), 'single @ removed';
  assert not app_private.valid_username('diego..p'), 'repeated separator rejected';
  assert not app_private.valid_username('_diego'), 'leading separator rejected';
  assert app_private.valid_username('diego_13'), 'internal separator accepted';
  assert not has_table_privilege('authenticated','app_private.username_claims','SELECT'), 'private registry not readable';
  assert not has_function_privilege('anon','public.read_my_profile_edit_state()','EXECUTE'), 'anonymous reader denied';
  assert not has_function_privilege('authenticated','public.before_user_created_username(jsonb)','EXECUTE'), 'hook not public RPC';
  assert not (select rolbypassrls from pg_roles where rolname='analog_profile_identity_executor'), 'executor not bypassrls';

  update app_private.identity_policy set require_username_for_signup=false where singleton;
  insert into auth.users(id,email,raw_user_meta_data,aud,role) values
    (a,a::text||'@identity.invalid','{"display_name":"QA Persona A"}','authenticated','authenticated'),
    (b,b::text||'@identity.invalid','{"display_name":"QA Persona B"}','authenticated','authenticated');
  insert into auth.sessions(id,user_id) values(sa,a),(sb,b);
  insert into public.profile_preferences(user_id,alias,bio,updated_at)
    values(a,'Alias anterior','Texto anterior','2020-01-01T00:00:00Z');
  insert into public.annual_film_goals(user_id,year,target_rolls) values(a,2026,10);
  insert into public.cameras(owner_user_id,maker,model,show_in_quick_mode)
    values(a,'QA IDENTITY','Camara propia',false) returning id into camera;
  insert into public.cameras(owner_user_id,maker,model)
    values(b,'QA IDENTITY','Camara ajena') returning id into foreign_camera;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
  perform set_config('role','authenticated',true);
  state:=public.read_my_profile_edit_state();
  assert state->>'user_id'=a::text, 'reader bound to caller';
  assert state->'identity'->>'revision'='0' and state->'identity'->>'username' is null, 'legacy not invented';
  assert state->'preferences'->>'alias'='Alias anterior', 'complete historical preferences';
  stamp:=(state->'preferences'->>'updated_at')::timestamptz;
  begin
    perform public.save_my_profile_edit(true,'qa_a_20261010','Intento inválido',null,foreign_camera,null,'0',stamp);
    raise exception 'Foreign favorite accepted';
  exception when sqlstate 'P1005' then null; end;
  state:=public.read_my_profile_edit_state();
  assert state->'identity'->>'revision'='0' and state->'preferences'->>'bio'='Texto anterior', 'failed favorite rolls back identity and prefs';
  begin
    perform public.save_my_profile_edit(true,'Dperabeles',null,null,null,null,'0',stamp);
    raise exception 'Reserved name accepted without beneficiary';
  exception when sqlstate 'P1002' then null; end;
  begin
    perform public.save_my_profile_edit(true,'diegoperabeles',null,null,null,null,'0',stamp);
    raise exception 'Blocked name accepted';
  exception when sqlstate 'P1002' then null; end;
  saved:=public.save_my_profile_edit(true,' @Qa_A_20261010 ','Presentación nueva',null,camera,null,'0',stamp);
  assert saved->'identity'->>'username'='qa_a_20261010' and saved->'identity'->>'revision'='1', 'first choice canonical and versioned';
  assert saved->'identity'->>'username_changed_at' is null, 'first choice consumes no rename';
  assert saved->'preferences'->>'alias'='Alias anterior', 'alias preserved on composed save';
  assert (saved->'preferences'->>'favorite_camera_id')::bigint=camera, 'own inactive camera valid';
  begin
    perform public.save_my_profile_edit(false,null,'Stale',null,camera,null,'0',stamp);
    raise exception 'Stale identity accepted';
  exception when sqlstate 'P1004' then null; end;
  begin
    perform public.save_my_profile_edit(true,'qa_stale_20261010','Stale',null,camera,null,'1',stamp);
    raise exception 'Stale preferences accepted';
  exception when sqlstate 'P1004' then null; end;
  stamp:=(saved->'preferences'->>'updated_at')::timestamptz;
  saved:=public.save_my_profile_edit(true,'qa_a_new_20261010','Presentación nueva',null,camera,null,'1',stamp);
  assert saved->'identity'->>'revision'='2', 'first rename allowed immediately';
  changed:=(saved->'identity'->>'username_changed_at')::timestamptz;
  assert (saved->'identity'->>'username_change_available_at')::timestamptz-changed=interval '720 hours', 'deadline server 720 hours';
  begin
    perform public.save_my_profile_edit(true,'qa_a_third_20261010',null,null,null,null,'2',(saved->'preferences'->>'updated_at')::timestamptz);
    raise exception 'Cooldown bypass accepted';
  exception when sqlstate 'P1003' then null; end;
  saved:=public.save_my_profile_edit(true,'QA_A_NEW_20261010','Sólo presentación',null,camera,null,'2',(saved->'preferences'->>'updated_at')::timestamptz);
  assert saved->'identity'->>'revision'='2' and (saved->'identity'->>'username_changed_at')::timestamptz=changed, 'case no-op consumes no change';
  assert saved->'preferences'->>'bio'='Sólo presentación', 'preferences editable during cooldown';
  begin
    perform public.save_my_profile_edit(true,'',null,null,null,null,'2',(saved->'preferences'->>'updated_at')::timestamptz);
    raise exception 'Assigned username cleared';
  exception when sqlstate 'P1001' then null; end;

  perform set_config('role','postgres',true);
  assert (select count(*) from public.annual_film_goals where user_id=a and year=2026 and target_rolls=10)=1, 'goal untouched';
  assert (select state='held' and owner_user_id is null and reserved_for_user_id is null
    from app_private.username_claims where username='qa_a_20261010'), 'hold retains no account link';
  update app_private.profile_identities set username_changed_at=clock_timestamp()-interval '719 hours 59 minutes' where user_id=a;
  perform set_config('role','authenticated',true);
  begin
    perform public.save_my_profile_edit(true,'qa_a_final_20261010',null,null,null,null,'2',(saved->'preferences'->>'updated_at')::timestamptz);
    raise exception 'Early cooldown boundary accepted';
  exception when sqlstate 'P1003' then null; end;
  perform set_config('role','postgres',true);
  update app_private.profile_identities set username_changed_at=clock_timestamp()-interval '720 hours' where user_id=a;
  perform set_config('role','authenticated',true);
  state:=public.read_my_profile_edit_state();
  assert state->'identity'->>'username_changed_at' is not null and state->'identity'->>'username_change_available_at' is null, 'expired cooldown is server-unlocked';
  saved:=public.save_my_profile_edit(true,'qa_a_final_20261010',null,null,null,null,'2',(saved->'preferences'->>'updated_at')::timestamptz);
  assert saved->'identity'->>'revision'='3', '720 hour boundary accepted';
  perform set_config('role','postgres',true);

  -- Reserved beneficiary comes only from trusted operator data, never metadata.
  update app_private.username_claims set reserved_for_user_id=b where username='dperabeles';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
  perform set_config('role','authenticated',true);
  saved:=public.save_my_profile_edit(true,'Dperabeles',null,null,null,null,'0',null);
  assert saved->'identity'->>'username'='dperabeles', 'beneficiary can activate own reservation';
  saved:=public.save_my_profile_edit(true,'qa_b_20261010',null,null,null,null,'1',(saved->'preferences'->>'updated_at')::timestamptz);
  perform set_config('role','postgres',true);
  assert (select state='reserved' and reserved_for_user_id=b from app_private.username_claims where username='dperabeles'), 'special name stays permanently reserved after rename';
  -- Existing hold cannot be reclaimed before expiry, even by its prior owner.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
  update app_private.profile_identities set username_changed_at=clock_timestamp()-interval '721 hours' where user_id=b;
  perform set_config('role','authenticated',true);
  begin
    perform public.save_my_profile_edit(true,'qa_a_20261010',null,null,null,null,'2',(saved->'preferences'->>'updated_at')::timestamptz);
    raise exception 'Unexpired hold reclaimed';
  exception when sqlstate 'P1002' then null; end;
  perform set_config('role','postgres',true);
  update app_private.username_claims set held_until=clock_timestamp()-interval '1 second' where username='qa_a_20261010';
  perform set_config('role','authenticated',true);
  saved:=public.save_my_profile_edit(true,'qa_a_20261010',null,null,null,null,'2',(saved->'preferences'->>'updated_at')::timestamptz);
  assert saved->'identity'->>'username'='qa_a_20261010', 'expired hold can be claimed without cron';
  perform set_config('role','postgres',true);

  -- Both directions are checked on COMMIT, including mutation from either table.
  begin
    insert into app_private.username_claims(username,state,owner_user_id) values('qa_orphan_20261010','active',c);
    raise exception 'Unknown account accepted';
  exception when foreign_key_violation then null; end;
  begin
    delete from app_private.profile_identities where user_id=a;
    set constraints all immediate;
    raise exception 'Orphan active claim accepted';
  exception when check_violation then null; end;
  set constraints all deferred;
  begin
    update app_private.username_claims set state='held',owner_user_id=null,held_until=clock_timestamp()+interval '1 hour'
      where username='qa_a_final_20261010';
    set constraints all immediate;
    raise exception 'Identity without active claim accepted';
  exception when check_violation then null; end;
  set constraints all deferred;

  -- Hook only preflights; final transaction remains authoritative.
  update app_private.identity_policy set require_username_for_signup=true where singleton;
  -- Managed Auth-admin cannot be SET ROLE by postgres on hosted Supabase.
  -- Here we prove hook logic; service permissions are exercised by Auth HTTP.
  assert has_function_privilege('supabase_auth_admin','public.before_user_created_username(jsonb)','EXECUTE'), 'Auth service has hook grant';
  state:=public.before_user_created_username(jsonb_build_object('user',jsonb_build_object('id',c,'user_metadata','{}'::jsonb)));
  assert state ? 'error', 'missing signup username preflight rejected';
  state:=public.before_user_created_username(jsonb_build_object('user',jsonb_build_object('id',c,'user_metadata','{"username":"qa_signup_20261010"}'::jsonb)));
  assert state='{}'::jsonb, 'valid signup preflight accepted without claim';
  perform set_config('role','postgres',true);
  assert not exists(select 1 from app_private.username_claims where username='qa_signup_20261010'), 'preflight creates no claim';
  begin
    insert into auth.users(id,email,raw_user_meta_data,aud,role) values(c,c::text||'@identity.invalid','{}','authenticated','authenticated');
    raise exception 'Mandatory signup username bypassed';
  exception when sqlstate 'P1001' then null; end;
  assert not exists(select 1 from auth.users where id=c), 'rejected signup leaves no account';
  insert into auth.users(id,email,raw_user_meta_data,aud,role) values(c,c::text||'@identity.invalid','{"username":"Qa_Signup_20261010","display_name":"QA Alta"}','authenticated','authenticated');
  assert (select username='qa_signup_20261010' from app_private.profile_identities where user_id=c), 'registration owns canonical handle atomically';
  begin
    insert into auth.users(id,email,raw_user_meta_data,aud,role) values(gen_random_uuid(),gen_random_uuid()::text||'@identity.invalid','{"username":"QA_SIGNUP_20261010"}','authenticated','authenticated');
    raise exception 'Duplicate signup handle accepted';
  exception when sqlstate 'P1002' then null; end;
  assert (select count(*) from app_private.username_claims where username='qa_signup_20261010')=1, 'single global claim';

  perform set_config('app.borrando_cuenta','si',true);
  begin
    delete from auth.users where id=a;
    assert (select state='held' and owner_user_id is null from app_private.username_claims where username='qa_a_final_20261010'), 'deletion immediately holds name';
    raise exception 'intentional_delete_rollback';
  exception when raise_exception then
    if sqlerrm<>'intentional_delete_rollback' then raise; end if;
  end;
  assert exists(select 1 from auth.users where id=a) and exists(select 1 from app_private.profile_identities where user_id=a), 'failed deletion restores account and identity';
  delete from auth.users where id=a;
  assert not exists(select 1 from public.profile_preferences where user_id=a), 'account data actually deleted';
  assert (select state='held' and owner_user_id is null from app_private.username_claims where username='qa_a_final_20261010'), 'ordinary deleted name quarantined';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id',sa)::text,true);
  perform set_config('role','authenticated',true);
  begin perform public.read_my_profile_edit_state(); raise exception 'Deleted account token accepted';
  exception when sqlstate 'P1006' then null; end;
  perform set_config('role','postgres',true);
  delete from auth.sessions where id=sb;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id',sb)::text,true);
  perform set_config('role','authenticated',true);
  begin perform public.read_my_profile_edit_state(); raise exception 'Revoked session accepted';
  exception when sqlstate 'P1006' then null; end;
  perform set_config('role','postgres',true);
  delete from auth.users where id=b;
  assert (select state='reserved' and reserved_for_user_id is null from app_private.username_claims where username='dperabeles'), 'deleted beneficiary does not free permanent reservation';
  perform app_private.cleanup_username_holds();
  assert exists(select 1 from app_private.username_claims where username='qa_signup_20261010' and state='active'), 'cleanup never removes active claim';
  set constraints all immediate;
  raise notice 'PASS: private identity behavioral matrix';
end $$;
select 'PASS: private identity behavioral matrix' as result;
