-- Review fix: the admin who published a policy stays private.
do $$
declare
  a uuid := pg_temp.buzon_user('fp_a');
  n int;
begin
  insert into public.inbox_policy_notices (title_es, title_en, summary_es, summary_en, url, effective_on, published_by)
  values ('t', 't', 's', 's', 'https://analog-archive.com/privacy', current_date + 5, a);
  perform pg_temp.como(a);
  select count(*) into n from public.inbox_policy_notices;
  assert n >= 1, 'the policy is readable';
  assert (select title_es from public.inbox_policy_notices where url = 'https://analog-archive.com/privacy' limit 1) = 't',
         'its content is readable';
  perform pg_temp.espera_error('select published_by from public.inbox_policy_notices', '42501');
  perform pg_temp.yo();
end $$;
