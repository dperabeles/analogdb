-- El aviso de registros nuevos dejó de funcionar.
--
-- Desde 20260526 los perfiles nacen con status 'approved' (sin aprobación
-- manual), pero el aviso filtraba por 'pending' en TRES lugares: el WHEN del
-- trigger, un early return en esta función, y una guarda en la Edge Function.
-- Resultado: nadie se enteraba de un registro nuevo.
--
-- Ahora avisa de CUALQUIER alta. El nombre `notify_pending_signup` se conserva
-- a propósito: la Edge Function desplegada vive en la URL
-- /functions/v1/notify-pending-signup y renombrar ambos lados a la vez no vale
-- el riesgo. Lee este comentario, no el nombre.

begin;

create or replace function public.notify_pending_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
begin
  -- Sin filtro por status: se avisa de todo registro nuevo. Antes había un
  -- early return por 'pending' que lo dejó mudo tras la auto-aprobación.
  begin
    select pac.config_value
    into webhook_secret
    from public.private_app_config pac
    where pac.config_key = 'pending_signup_webhook_secret'
    limit 1;

    if webhook_secret is null or webhook_secret = '' then
      raise notice 'signup notification skipped: missing vault secret';
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
    -- El aviso NUNCA debe tumbar un registro: si falla, se anota y sigue.
    when others then
      raise notice 'signup notification skipped: %', sqlerrm;
  end;

  return new;
end;
$$;

-- El trigger también filtraba por 'pending' en su WHEN.
drop trigger if exists profiles_notify_pending_signup on public.profiles;
create trigger profiles_notify_pending_signup
after insert on public.profiles
for each row
execute function public.notify_pending_signup();

commit;
