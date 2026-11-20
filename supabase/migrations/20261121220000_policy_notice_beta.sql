-- During the TestFlight beta a policy change takes effect when its notice
-- is published (Diego, 20-nov; privacy §16, terms §22, cookies §11). The
-- notice still goes first: in the inbox and, when the change comes with a
-- build, in its TestFlight notes. From the App Store launch a migration sets
-- this back to 5 days.
create function app_private.policy_notice_min_days()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 0
$$;
revoke all on function app_private.policy_notice_min_days() from public, anon, authenticated;

create or replace function public.inbox_publish_policy(p_title_es text, p_title_en text, p_summary_es text,
                                                      p_summary_en text, p_url text, p_effective_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := app_private.inbox_caller();
  v_at timestamptz := now();
  v_id uuid;
begin
  if not public.app_is_admin(v_uid) then
    raise exception 'not_admin' using errcode = 'P1205';
  end if;
  if nullif(btrim(p_title_es), '') is null or nullif(btrim(p_title_en), '') is null
     or nullif(btrim(p_summary_es), '') is null or nullif(btrim(p_summary_en), '') is null
     or p_url is null or p_url not like 'https://%' or p_effective_on is null then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;
  if p_effective_on < (v_at at time zone 'America/Mexico_City')::date + app_private.policy_notice_min_days() then
    raise exception 'policy_notice_too_soon' using errcode = 'P1206';
  end if;

  insert into public.inbox_policy_notices
    (title_es, title_en, summary_es, summary_en, url, effective_on, published_at, published_by)
  values (btrim(p_title_es), btrim(p_title_en), btrim(p_summary_es), btrim(p_summary_en), p_url,
          p_effective_on, v_at, v_uid)
  returning id into v_id;

  insert into public.inbox_notices (owner_user_id, kind, policy_id, detected_at, shown_at, rang_at)
  select p.user_id, 'policy_change', v_id, v_at, v_at, v_at
  from public.profiles p
  where p.created_at < v_at;

  perform app_private.push_flush();
  return v_id;
end;
$$;
