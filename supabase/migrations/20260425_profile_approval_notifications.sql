begin;

create or replace function public.notify_profile_approved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
begin
  if new.status is distinct from 'approved'
    or old.status is not distinct from 'approved' then
    return new;
  end if;

  begin
    select pac.config_value
    into webhook_secret
    from public.private_app_config pac
    where pac.config_key = 'pending_signup_webhook_secret'
    limit 1;

    if webhook_secret is null or webhook_secret = '' then
      raise notice 'profile approval notification skipped: missing webhook secret';
      return new;
    end if;

    perform net.http_post(
      url := 'https://dqjjxxqruxxfsfoejdzl.supabase.co/functions/v1/notify-profile-approved',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'type', tg_op,
        'schema', tg_table_schema,
        'table', tg_table_name,
        'old_record', to_jsonb(old),
        'record', to_jsonb(new)
      )
    );
  exception
    when others then
      raise notice 'profile approval notification skipped: %', sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists profiles_notify_approved on public.profiles;
create trigger profiles_notify_approved
after update of status on public.profiles
for each row
when (new.status = 'approved' and old.status is distinct from 'approved')
execute function public.notify_profile_approved();

revoke all on function public.notify_profile_approved() from public;
revoke all on function public.notify_profile_approved() from anon;
revoke all on function public.notify_profile_approved() from authenticated;

commit;
