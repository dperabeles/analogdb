begin;

create extension if not exists pg_net;

create table if not exists public.private_app_config (
  config_key text primary key,
  config_value text not null,
  updated_at timestamptz not null default now()
);

create or replace function public.notify_pending_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
begin
  if new.status is distinct from 'pending' then
    return new;
  end if;

  begin
    select pac.config_value
    into webhook_secret
    from public.private_app_config pac
    where pac.config_key = 'pending_signup_webhook_secret'
    limit 1;

    if webhook_secret is null or webhook_secret = '' then
      raise notice 'pending signup notification skipped: missing vault secret';
      return new;
    end if;

    perform net.http_post(
      url := 'https://dqjjxxqruxxfsfoejdzl.supabase.co/functions/v1/notify-pending-signup',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'type', tg_op,
        'schema', tg_table_schema,
        'table', tg_table_name,
        'record', to_jsonb(new)
      )
    );
  exception
    when others then
      raise notice 'pending signup notification skipped: %', sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists profiles_notify_pending_signup on public.profiles;
create trigger profiles_notify_pending_signup
after insert on public.profiles
for each row
when (new.status = 'pending')
execute function public.notify_pending_signup();

revoke all on public.private_app_config from anon, authenticated;
alter table public.private_app_config enable row level security;

revoke all on function public.notify_pending_signup() from public;
revoke all on function public.notify_pending_signup() from anon;
revoke all on function public.notify_pending_signup() from authenticated;

commit;
