-- Push notifications (ANA-74), part 1: the outbox and the FCM token.
--
-- What rings in the inbox (the develop reminder, a policy notice) is queued
-- here; send-push delivers it later. Only these two kinds go to the phone: the
-- data-gap notices stay in the inbox.
--
-- The token is written only through register_push_token, which first takes it
-- away from any other account. Two people on the same phone must never get
-- each other's notices.

create table app_private.push_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  notice_id uuid not null references public.inbox_notices (id) on delete cascade,
  kind text not null check (kind in ('develop_reminder', 'policy_change')),
  rang_at timestamptz not null,
  created_at timestamptz not null default now(),
  attempts int not null default 0,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'skipped')),
  sent_at timestamptz,
  unique (notice_id, rang_at)
);

create index push_outbox_pending_idx on app_private.push_outbox (created_at) where status = 'pending';
create index push_outbox_user_idx on app_private.push_outbox (user_id);

revoke all on table app_private.push_outbox from public, anon, authenticated;

create function app_private.push_enqueue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind in ('develop_reminder', 'policy_change')
     and new.rang_at is not null
     and (tg_op = 'INSERT' or old.rang_at is distinct from new.rang_at) then
    insert into app_private.push_outbox (user_id, notice_id, kind, rang_at)
    values (new.owner_user_id, new.id, new.kind, new.rang_at)
    on conflict (notice_id, rang_at) do nothing;
  end if;
  return new;
end;
$$;

revoke all on function app_private.push_enqueue() from public, anon, authenticated;

create trigger inbox_notices_push_enqueue
after insert or update of rang_at on public.inbox_notices
for each row execute function app_private.push_enqueue();

-- The token only moves through these two functions.
revoke update (fcm_token, fcm_platform, fcm_token_updated_at) on public.profiles from authenticated;

create function public.register_push_token(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_token is null or btrim(p_token) = '' or char_length(p_token) > 4096
     or p_platform is null or p_platform not in ('ios', 'android') then
    raise exception 'invalid_input' using errcode = 'P1203';
  end if;

  -- Same phone, another account: that account stops receiving on it.
  update public.profiles
     set fcm_token = null, fcm_platform = null, fcm_token_updated_at = now()
   where fcm_token = p_token and user_id <> v_uid;

  update public.profiles
     set fcm_token = p_token, fcm_platform = p_platform, fcm_token_updated_at = now()
   where user_id = v_uid;
end;
$$;

create function public.clear_push_token()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  update public.profiles
     set fcm_token = null, fcm_platform = null, fcm_token_updated_at = now()
   where user_id = v_uid;
end;
$$;

revoke all on function public.register_push_token(text, text), public.clear_push_token() from public, anon;
grant execute on function public.register_push_token(text, text), public.clear_push_token() to authenticated;
