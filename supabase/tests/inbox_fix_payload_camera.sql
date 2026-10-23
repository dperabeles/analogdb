-- Review fix: notices about a roll carry that roll's camera, as the plan shows.
do $$
declare
  a uuid := pg_temp.buzon_user('fc_a');
  cam bigint := pg_temp.buzon_camera(a, 'Leica M');
  rn bigint; ro bigint; l jsonb;
begin
  ro := pg_temp.buzon_roll(a, 'Developed', cam);
  update public.rolls set created_at = now() - interval '2 days' where id = ro;
  perform pg_temp.como(a);
  perform public.inbox_list();
  perform pg_temp.yo();
  rn := pg_temp.buzon_roll(a, 'Developed', cam);
  insert into public.inbox_notices (owner_user_id, kind, roll_id, detected_at, shown_at, rang_at)
  values (a, 'missing_lens', rn, now(), now(), now());
  perform pg_temp.como(a);
  l := public.inbox_list();
  perform pg_temp.yo();
  assert (select (x -> 'camera' ->> 'id')::bigint from jsonb_array_elements(l -> 'notices') x
          where x ->> 'kind' = 'missing_lens') = cam, 'missing_lens carries the roll camera';
  assert (select (i -> 'camera' ->> 'id')::bigint
          from jsonb_array_elements(l -> 'notices') x, jsonb_array_elements(x -> 'items') i
          where x ->> 'kind' = 'backlog_incomplete' and (i -> 'roll' ->> 'id')::bigint = ro limit 1) = cam,
         'group items carry the roll camera';
end $$;
