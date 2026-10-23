-- Inbox API: what the app calls.
create function pg_temp.list_as(p_uid uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.como(p_uid);
  v := public.inbox_list();
  perform pg_temp.yo();
  return v;
end $$;

create function pg_temp.find(p_list jsonb, p_id uuid) returns jsonb language sql as $$
  select e from jsonb_array_elements(p_list -> 'notices') e where e ->> 'id' = p_id::text;
$$;

do $$
declare
  a uuid := pg_temp.buzon_user('api_a');
  a2 uuid := pg_temp.buzon_user('api_a2');
  b uuid := pg_temp.buzon_user('api_b');
  adm uuid := pg_temp.buzon_user('api_adm');
  p uuid := pg_temp.buzon_user('api_p', 'pending');
  rj uuid := pg_temp.buzon_user('api_rj', 'rejected');
  z uuid := pg_temp.buzon_user('api_z');
  cam bigint := pg_temp.buzon_camera(a, 'Leica M');
  qc bigint := pg_temp.buzon_camera(a);
  cam_b bigint := pg_temp.buzon_camera(b);
  lab bigint;
  ro bigint; rn bigint; rq bigint; rb bigint; rz bigint;
  nb uuid; nn uuid; nq uuid; l jsonb; e jsonb; k int; fn text;
begin
  insert into public.labs (name, status) values ('Lab buzon test', 'approved') returning id into lab;

  -- First call: activates and shows the old-rolls group in the same response.
  ro := pg_temp.buzon_roll(a, 'Developed', cam, pg_temp.buzon_lens(a));
  update public.rolls set created_at = now() - interval '1 day' where id = ro;
  l := pg_temp.list_as(a);
  assert exists (select 1 from public.inbox_accounts where user_id = a), 'activated';
  assert (select count(*) from jsonb_array_elements(l -> 'notices') x where x ->> 'kind' = 'backlog_incomplete') = 1,
         'group in the first response';
  assert (l ->> 'unread')::int = 1, 'one unread';
  assert l ? 'admin' and l ? 'seen_keys' and (l -> 'admin') = 'null'::jsonb, 'shape, no admin block';
  e := (l -> 'notices') -> 0;
  assert e ? 'read' and e ? 'resolved' and e ? 'pinned' and e ? 'items' and e ? 'roll' and e ? 'camera' and e ? 'policy',
         'notice shape';
  assert jsonb_array_length(e -> 'items') = 1 and (e -> 'items' -> 0 -> 'roll' ->> 'id')::bigint = ro, 'group lists the old roll';

  -- inbox_unread_count also activates.
  perform pg_temp.como(a2);
  k := public.inbox_unread_count();
  perform pg_temp.yo();
  assert exists (select 1 from public.inbox_accounts where user_id = a2), 'unread count activates';

  -- A shown notice whose data gets completed reads as resolved without evaluating.
  rn := pg_temp.buzon_roll(a, 'Developed', cam, pg_temp.buzon_lens(a));
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at)
  values (a, 'missing_lab', rn, now(), now(), now()) returning id into nn;
  update public.rolls set dev_lab_id = lab where id = rn;
  assert (pg_temp.find(pg_temp.list_as(a), nn) ->> 'resolved')::boolean, 'resolved on read';

  -- Marking only touches your own notices.
  rb := pg_temp.buzon_roll(b, 'Developed');
  insert into public.inbox_accounts (user_id, activated_at) values (b, now());
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at)
  values (b, 'missing_lab', rb, now(), now(), now()) returning id into nb;
  perform pg_temp.como(a);
  assert public.inbox_mark(array[nb], true) = 0, 'B notice not touched';
  perform pg_temp.yo();
  assert (select read_at from public.inbox_notices where id = nb) is null, 'B notice still unread';

  -- Review Focus 5: retries in any order.
  select n.id into nn from public.inbox_notices n where n.owner_user_id = a and n.kind = 'backlog_incomplete';
  perform pg_temp.como(a);
  assert public.inbox_mark(array[nn], true) = 1, 'first mark changes one';
  assert public.inbox_mark(array[nn], true) = 0, 'second mark changes nothing';
  assert public.inbox_mark(array[nn], false) = 1, 'unread again';
  perform pg_temp.espera_error('select public.inbox_mark(null, true)', 'P1203');
  perform pg_temp.yo();
  delete from public.inbox_notices where id = nn;
  perform pg_temp.como(a);
  assert public.inbox_mark(array[nn], true) = 0, 'cleaned notice: no error';
  perform pg_temp.yo();

  -- Mark everything read.
  l := pg_temp.list_as(a);
  perform pg_temp.como(a);
  perform public.inbox_mark_all_read();
  assert public.inbox_unread_count() = 0, 'all read';
  perform pg_temp.yo();
  assert (select admin_read_at from public.inbox_accounts where user_id = a) is not null, 'admin_read_at set';

  -- The admin block, only for admins.
  perform pg_temp.buzon_admin(adm);
  insert into public.labs (name) values ('Lab buzon pending');
  l := pg_temp.list_as(adm);
  assert (l -> 'admin' ->> 'labs_pending')::int = (select count(*) from public.labs where status = 'pending'),
         'labs pending counted';
  assert (l -> 'admin' ->> 'has_news')::boolean, 'news before reading';
  perform pg_temp.como(adm);
  perform public.inbox_mark_admin(true);
  perform pg_temp.yo();
  assert not (pg_temp.list_as(adm) -> 'admin' ->> 'has_news')::boolean, 'read';
  -- labs_force_submission stamps created_at on insert; date it after reading.
  insert into public.labs (name) values ('Lab buzon pending 2');
  update public.labs set created_at = now() + interval '1 minute' where name = 'Lab buzon pending 2';
  assert (pg_temp.list_as(adm) -> 'admin' ->> 'has_news')::boolean, 'a new pending lab is news';
  perform pg_temp.como(a);
  perform pg_temp.espera_error('select public.inbox_mark_admin(true)', 'P1205');
  perform pg_temp.yo();

  -- Dismissing the group.
  update public.rolls set dev_lab_id = null where id = ro;
  perform app_private.inbox_evaluate(a, now());
  perform pg_temp.como(a);
  assert public.inbox_dismiss_backlog(), 'dismissed';
  perform pg_temp.yo();
  perform app_private.inbox_evaluate(a, now() + interval '1 day');
  assert not exists (select 1 from jsonb_array_elements(pg_temp.list_as(a) -> 'notices') x
                     where x ->> 'kind' = 'backlog_incomplete'), 'group gone and stays gone';

  -- The camera question.
  rq := pg_temp.buzon_roll(a, 'Developed', qc);
  update public.rolls set dev_lab_id = lab where id = rq;
  insert into public.inbox_notices (owner_user_id, kind, camera_id, detected_at, shown_at, rang_at)
  values (a, 'camera_lens_question', qc, now(), now(), now()) returning id into nq;
  perform pg_temp.como(a);
  perform pg_temp.espera_error(format('select public.inbox_answer_camera_lens(%s, false)', cam_b), 'P1204');
  perform pg_temp.espera_error(format('select public.inbox_answer_camera_lens(%s, null)', qc), 'P1203');
  perform public.inbox_answer_camera_lens(qc, false);
  perform pg_temp.yo();
  assert (select resolved_at from public.inbox_notices where id = nq) is not null, 'question resolved';
  assert (select not supports_interchangeable_lenses and lens_setup_confirmed_at is not null
          from public.cameras where id = qc), 'camera marked fixed';
  perform app_private.inbox_evaluate(a, now() + interval '5 days');
  assert not exists (select 1 from public.inbox_notices where owner_user_id = a and roll_id = rq and kind = 'missing_lens'),
         'no lens asked after "fixed lens"';
  assert (select count(*) from public.inbox_notices where camera_id = qc) = 1, 'no new question';

  -- Seen keys.
  perform pg_temp.como(a);
  perform pg_temp.espera_error($q$select public.inbox_mark_seen(array['News:X'])$q$, 'P1203');
  perform public.inbox_mark_seen(array['news:inventory']);
  perform public.inbox_mark_seen(array['news:inventory']);
  perform pg_temp.yo();
  assert (select count(*) from public.inbox_seen_keys where user_id = a) = 1, 'one seen key';
  assert (pg_temp.list_as(a) -> 'seen_keys') ? 'news:inventory', 'seen key listed';

  -- Pending, rejected and no session.
  foreach fn in array array['select public.inbox_list()', 'select public.inbox_unread_count()',
                            'select public.inbox_mark(array[gen_random_uuid()], true)',
                            'select public.inbox_mark_all_read()', 'select public.inbox_dismiss_backlog()',
                            'select public.inbox_mark_admin(true)',
                            'select public.inbox_answer_camera_lens(1, true)',
                            $q$select public.inbox_mark_seen(array['news:x'])$q$] loop
    perform pg_temp.como(p);
    perform pg_temp.espera_error(fn, 'P1202');
    perform pg_temp.como(rj);
    perform pg_temp.espera_error(fn, 'P1202');
    perform pg_temp.como(null);
    perform pg_temp.espera_error(fn, '42501');
    perform pg_temp.yo();
  end loop;

  -- Deleting a roll or a camera takes its notices; nothing of the inbox goes to the trash.
  perform pg_temp.como(a);
  delete from public.rolls where id = rq;
  delete from public.cameras where id = qc;
  perform pg_temp.yo();
  assert not exists (select 1 from public.inbox_notices where roll_id = rq or camera_id = qc), 'notices went with them';
  assert not exists (select 1 from public.deleted_rows where tabla like 'inbox%'), 'no inbox rows in the trash';

  -- Closing an account leaves nothing of its inbox.
  rz := pg_temp.buzon_roll(z, 'To Develop');
  perform pg_temp.como(z);
  perform public.inbox_list();
  perform public.inbox_mark_seen(array['news:x']);
  perform pg_temp.yo();
  insert into public.inbox_develop_rings (roll_id, owner_user_id, started_at) values (rz, z, now())
  on conflict do nothing;  -- activation may have created it already
  insert into public.inbox_suppressions (owner_user_id, roll_id, field) values (z, rz, 'camera');
  perform pg_temp.como(z);
  perform public.delete_my_account();
  perform pg_temp.yo();
  assert not exists (select 1 from public.inbox_accounts where user_id = z)
     and not exists (select 1 from public.inbox_notices where owner_user_id = z)
     and not exists (select 1 from public.inbox_seen_keys where user_id = z)
     and not exists (select 1 from public.inbox_develop_rings where owner_user_id = z)
     and not exists (select 1 from public.inbox_suppressions where owner_user_id = z), 'account inbox gone';
end $$;
