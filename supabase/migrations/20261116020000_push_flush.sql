-- Push notifications (ANA-74), part 2: send-push claims what is queued,
-- reports how it went, and the database tells it when to look.
--
-- A claimed row is leased for 2 minutes, so two flushes that overlap (the
-- hourly tick and a policy publish) never send the same row twice. Only rows
-- that can go out now are handed out: inside 08:00–21:59 in the account's
-- zone, or older than 24 hours (those are handed out only to be skipped).

alter table app_private.push_outbox add column claimed_at timestamptz;

create function public.push_claim(p_limit int default 100, p_now timestamptz default now())
returns table (
  outbox_id uuid, user_id uuid, kind text, rang_at timestamptz, attempts int,
  fcm_token text, fcm_platform text, locale text, zone text, legal_updates boolean,
  develop_count int, title_es text, title_en text, summary_es text, summary_en text
)
language sql
security definer
set search_path = ''
as $$
  with c as (
    select o.id
    from app_private.push_outbox o
    where o.status = 'pending'
      and (o.claimed_at is null or o.claimed_at <= p_now - interval '2 minutes')
      and (o.rang_at <= p_now - interval '24 hours'
           or (p_now at time zone app_private.inbox_zone(o.user_id))::time
                between time '08:00' and time '21:59:59')
    order by o.created_at, o.id
    limit greatest(1, least(coalesce(p_limit, 100), 500))
    for update skip locked
  ),
  u as (
    update app_private.push_outbox o
       set claimed_at = p_now
      from c
     where o.id = c.id
    returning o.*
  )
  select u.id, u.user_id, u.kind, u.rang_at, u.attempts,
         p.fcm_token, p.fcm_platform,
         coalesce(nullif(au.raw_user_meta_data ->> 'locale', ''), 'es'),
         app_private.inbox_zone(u.user_id),
         coalesce((p.notification_prefs ->> 'legal_updates')::boolean, true),
         case when u.kind = 'develop_reminder'
              then (select count(*)::int from app_private.inbox_develop_waiting(u.user_id, p_now)) end,
         pn.title_es, pn.title_en, pn.summary_es, pn.summary_en
  from u
  join public.profiles p on p.user_id = u.user_id
  join auth.users au on au.id = u.user_id
  left join public.inbox_notices n on n.id = u.notice_id
  left join public.inbox_policy_notices pn on pn.id = n.policy_id;
$$;

-- p_status: sent | failed | retry | opted_out | skipped | release.
-- Returns the row's status afterwards. retry counts an attempt; the third
-- one fails. release only gives the lease back.
create function public.push_complete(p_outbox_id uuid, p_status text, p_fcm_code int,
                                     p_title text, p_body text, p_clear_token boolean,
                                     p_token text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  o app_private.push_outbox;
  v_final text;
  v_log text;
begin
  if p_status is null or p_status not in ('sent', 'failed', 'retry', 'opted_out', 'skipped', 'release') then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;
  select * into o from app_private.push_outbox where id = p_outbox_id for update;
  if not found then
    return null;
  end if;

  if p_status = 'release' then
    update app_private.push_outbox set claimed_at = null where id = o.id;
    return 'pending';
  end if;

  v_final := case p_status
               when 'sent' then 'sent'
               when 'failed' then 'failed'
               when 'retry' then case when o.attempts + 1 >= 3 then 'failed' else 'pending' end
               else 'skipped'
             end;
  v_log := case
             when p_status = 'sent' then 'sent'
             when p_status = 'opted_out' then 'opted_out'
             when v_final = 'failed' then 'failed'
           end;

  update app_private.push_outbox
     set status = v_final,
         attempts = attempts + case when p_status = 'retry' then 1 else 0 end,
         claimed_at = null,
         sent_at = case when v_final = 'sent' then now() else sent_at end
   where id = o.id;

  if v_log is not null then
    insert into public.push_log (user_id, type, title, body, status, fcm_response_code)
    values (o.user_id, o.kind, coalesce(p_title, ''), coalesce(p_body, ''), v_log, p_fcm_code);
  end if;

  -- A dead token is removed only if the account still has that same one.
  if p_clear_token and p_token is not null then
    update public.profiles
       set fcm_token = null, fcm_platform = null, fcm_token_updated_at = now()
     where user_id = o.user_id and fcm_token = p_token;
  end if;

  return v_final;
end;
$$;

-- Only send-push calls these. The backend role keeps EXECUTE through the
-- project's default privileges; users and anon lose it here.
revoke all on function public.push_claim(int, timestamptz),
  public.push_complete(uuid, text, int, text, text, boolean, text) from public, anon, authenticated;

-- Tells send-push to look. Off until both keys exist in this environment.
create function app_private.push_flush()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text := (select c.config_value from public.private_app_config c where c.config_key = 'push_flush_url');
  v_secret text := (select c.config_value from public.private_app_config c where c.config_key = 'push_flush_secret');
begin
  if nullif(v_url, '') is null or nullif(v_secret, '') is null then
    return;
  end if;
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
      body := '{}'::jsonb
    );
  exception when others then
    raise warning 'push_flush: % %', sqlstate, sqlerrm;
  end;
end;
$$;

-- Finished rows and the log are kept 90 days.
create function app_private.push_cleanup(p_now timestamptz)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from app_private.push_outbox o
   where o.status <> 'pending' and o.created_at <= p_now - interval '90 days';
  delete from public.push_log l
   where l.created_at <= p_now - interval '90 days';
$$;

revoke all on function app_private.push_flush(), app_private.push_cleanup(timestamptz)
  from public, anon, authenticated;

-- The hourly tick and policy publishing now end by flushing. Bodies copied
-- from the versions in force (inbox_minor_fixes, inbox_policy).
create or replace function app_private.inbox_tick(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_count integer := 0;
begin
  for v_uid in
    select a.user_id from public.inbox_accounts a
    where (p_now at time zone app_private.inbox_zone(a.user_id))::time >= time '08:00'
      and (a.last_evaluated_on is null
           or a.last_evaluated_on < app_private.inbox_local_date(a.user_id, p_now))
  loop
    begin
      perform app_private.inbox_evaluate(v_uid, p_now);
      v_count := v_count + 1;
    exception when others then
      update public.inbox_accounts
         set last_error = left(sqlstate || ': ' || sqlerrm, 500), last_error_at = p_now
       where user_id = v_uid;
      raise warning 'inbox_tick: % falló: % %', v_uid, sqlstate, sqlerrm;
    end;
  end loop;

  begin
    perform app_private.push_cleanup(p_now);
  exception when others then
    raise warning 'inbox_tick: push_cleanup falló: % %', sqlstate, sqlerrm;
  end;
  perform app_private.push_flush();
  return v_count;
end;
$$;

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
  if p_effective_on < (v_at at time zone 'America/Mexico_City')::date + 5 then
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
