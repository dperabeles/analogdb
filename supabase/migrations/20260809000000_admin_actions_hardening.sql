-- Endurecimiento del flujo de cambios de rol de admin (ANA-112).
--
-- El diseño existente ya era bueno: unanimidad entre los admins elegibles,
-- nadie se cambia el rol a sí mismo, el afectado no vota sobre su propio
-- caso, y al founder no se le puede degradar. Todo eso se conserva intacto.
--
-- Lo que le faltaba eran cuatro cosas, y ninguna se podía improvisar después
-- sin migrar datos vivos:
--
--   1. CANCELAR — la tabla contemplaba el estado 'cancelled' pero ninguna
--      función lo escribía nunca. Una propuesta hecha por error se quedaba
--      'pending' para siempre.
--   2. CADUCAR — con unanimidad, un admin que deja de responder bloquea toda
--      promoción futura sin necesidad de rechazarla. Sin caducidad, esa
--      propuesta zombi vive indefinidamente.
--   3. MOTIVO — el sistema escribía `resolved_reason`, pero quien proponía no
--      podía dejar constancia del porqué. Para un registro de auditoría eso
--      es la mitad del valor.
--   4. AVISO — nadie se enteraba de que existía una propuesta pendiente ni de
--      que un cambio de rol se había ejecutado.
--
-- Contexto al aplicarla: `admin_actions` tiene CERO filas en producción — el
-- sistema nunca se ha usado. No hay datos que migrar ni compatibilidad hacia
-- atrás que preservar más allá de la webapp, que sí llama estas funciones.

begin;

-- ── 1. Columnas nuevas ────────────────────────────────────────────────────

alter table public.admin_actions
  add column if not exists request_reason text,
  add column if not exists expires_at timestamptz;

comment on column public.admin_actions.request_reason is
  'Por qué se propuso el cambio. Lo escribe quien propone; complementa a resolved_reason, que lo escribe el sistema al resolver.';
comment on column public.admin_actions.expires_at is
  'A partir de aquí la propuesta ya no se puede votar y se auto-cancela. NULL = sin caducidad (filas anteriores a esta migración).';


-- ── 2. request_admin_action: motivo + caducidad + idempotencia ────────────
--
-- Se DROPEA la versión de dos argumentos a propósito. Si conviven las dos,
-- PostgREST no sabe cuál elegir cuando el cuerpo trae solo dos claves y
-- responde "Could not choose the best candidate function" — eso rompería el
-- panel de la webapp, que llama exactamente con dos. Con una sola función y
-- el tercer parámetro por defecto, la llamada de dos claves sigue sirviendo
-- sin tocar una línea de la web.

drop function if exists public.request_admin_action(text, uuid);

create or replace function public.request_admin_action(
  p_action_type text,
  p_target_user_id uuid,
  p_reason text default null
)
returns public.admin_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  created_action public.admin_actions;
  existing_action public.admin_actions;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  if p_action_type not in ('promote_to_admin', 'demote_from_admin') then
    raise exception 'invalid action type';
  end if;

  if p_target_user_id = actor_id then
    raise exception 'self role changes are not allowed';
  end if;

  if p_action_type = 'demote_from_admin' and public.app_is_founder(p_target_user_id) then
    raise exception 'founder admin cannot be demoted';
  end if;

  -- Idempotente: si ya hay una propuesta viva para el mismo usuario y el
  -- mismo tipo, se devuelve esa en vez de crear una segunda.
  --
  -- Se eligió devolver y no lanzar excepción para no estrenar un camino de
  -- error nuevo en el panel de la webapp, que hoy no lo espera. El efecto
  -- práctico es el mismo: no se acumulan duplicados, que era lo que hacía
  -- incoherente poder cancelar (cancelas una y la gemela sigue viva).
  select *
  into existing_action
  from public.admin_actions
  where action_type = p_action_type
    and target_user_id = p_target_user_id
    and status = 'pending'
    and (expires_at is null or now() <= expires_at)
  order by created_at desc
  limit 1;

  if found then
    return existing_action;
  end if;

  insert into public.admin_actions (
    action_type, target_user_id, created_by, status, request_reason, expires_at
  )
  values (
    p_action_type,
    p_target_user_id,
    actor_id,
    'pending',
    nullif(btrim(coalesce(p_reason, '')), ''),
    now() + interval '30 days'
  )
  returning * into created_action;

  return created_action;
end;
$$;


-- ── 3. cancel_admin_action: retirar una propuesta ─────────────────────────
--
-- Quién puede: solo quien la propuso, o el founder.
--
-- A propósito NO cualquier admin: para decir "no estoy de acuerdo" ya existe
-- el voto de rechazo, que deja constancia de la decisión. Cancelar es para
-- "me equivoqué" o para que el founder limpie, y borra la propuesta del
-- radar sin registrar un juicio sobre ella.

create or replace function public.cancel_admin_action(
  p_action_id uuid,
  p_reason text default null
)
returns public.admin_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  action_row public.admin_actions;
  actor_is_requester boolean;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  select *
  into action_row
  from public.admin_actions
  where id = p_action_id;

  if not found then
    raise exception 'admin action not found';
  end if;

  -- Idempotente: si ya se resolvió (ejecutada, rechazada o cancelada), se
  -- devuelve tal cual. Cancelar dos veces no es un error.
  if action_row.status <> 'pending' then
    return action_row;
  end if;

  actor_is_requester := action_row.created_by = actor_id;

  if not actor_is_requester and not public.app_is_founder(actor_id) then
    raise exception 'only the requester or the founder can cancel';
  end if;

  update public.admin_actions
  set
    status = 'cancelled',
    resolved_at = now(),
    resolved_reason = coalesce(
      nullif(btrim(coalesce(p_reason, '')), ''),
      case when actor_is_requester
        then 'Cancelled by requester'
        else 'Cancelled by founder'
      end
    )
  where id = p_action_id
  returning * into action_row;

  return action_row;
end;
$$;


-- ── 4. cast_admin_action_vote: respetar la caducidad ──────────────────────
--
-- Única diferencia respecto a la versión anterior: el bloque de caducidad,
-- marcado abajo. Todo lo demás se reproduce igual — `create or replace`
-- sustituye el cuerpo completo, así que no se puede parchear a trozos.
--
-- La comprobación es null-safe: una fila sin `expires_at` (las anteriores a
-- esta migración, de las que hoy no existe ninguna) se comporta exactamente
-- como antes. La webapp no necesita ningún cambio: misma firma, mismo tipo
-- de retorno.

create or replace function public.cast_admin_action_vote(p_action_id uuid, p_decision text)
returns public.admin_actions
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  action_row public.admin_actions;
  target_is_founder boolean;
  eligible_admin_count integer;
  approved_vote_count integer;
  has_rejection boolean;
begin
  if not public.app_is_admin(actor_id) then
    raise exception 'admin required';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid decision';
  end if;

  select *
  into action_row
  from public.admin_actions
  where id = p_action_id;

  if not found then
    raise exception 'admin action not found';
  end if;

  if action_row.status <> 'pending' then
    return action_row;
  end if;

  -- ▼ NUEVO: caducidad. Una propuesta vencida no se vota; se auto-cancela.
  if action_row.expires_at is not null and now() > action_row.expires_at then
    update public.admin_actions
    set
      status = 'cancelled',
      resolved_at = now(),
      resolved_reason = 'Expired without unanimous approval'
    where id = p_action_id
    returning * into action_row;
    return action_row;
  end if;
  -- ▲ NUEVO

  if action_row.target_user_id = actor_id then
    raise exception 'target user cannot vote on own role change';
  end if;

  target_is_founder := public.app_is_founder(action_row.target_user_id);
  if action_row.action_type = 'demote_from_admin' and target_is_founder then
    update public.admin_actions
    set
      status = 'rejected',
      resolved_at = now(),
      resolved_reason = 'Founder admin cannot be demoted'
    where id = p_action_id
    returning * into action_row;
    return action_row;
  end if;

  insert into public.admin_action_approvals (action_id, admin_user_id, decision)
  values (p_action_id, actor_id, p_decision)
  on conflict (action_id, admin_user_id)
  do update set decision = excluded.decision, decided_at = now();

  select exists(
    select 1
    from public.admin_action_approvals aaa
    where aaa.action_id = p_action_id
      and aaa.decision = 'rejected'
  ) into has_rejection;

  if has_rejection then
    update public.admin_actions
    set
      status = 'rejected',
      resolved_at = now(),
      resolved_reason = 'Rejected by admin vote'
    where id = p_action_id
    returning * into action_row;
    return action_row;
  end if;

  select count(*)
  into eligible_admin_count
  from public.user_roles ur
  where ur.role = 'admin'
    and ur.user_id <> action_row.target_user_id;

  select count(*)
  into approved_vote_count
  from public.admin_action_approvals aaa
  where aaa.action_id = p_action_id
    and aaa.decision = 'approved';

  if approved_vote_count < eligible_admin_count then
    return action_row;
  end if;

  if action_row.action_type = 'promote_to_admin' then
    insert into public.user_roles (user_id, role, is_founder, granted_by)
    values (action_row.target_user_id, 'admin', false, actor_id)
    on conflict (user_id)
    do update set role = 'admin', granted_by = actor_id;
  elsif action_row.action_type = 'demote_from_admin' then
    update public.user_roles
    set role = 'user', granted_by = actor_id
    where user_id = action_row.target_user_id
      and is_founder = false;
  end if;

  update public.admin_actions
  set
    status = 'executed',
    resolved_at = now(),
    resolved_reason = 'Unanimous approval reached'
  where id = p_action_id
  returning * into action_row;

  return action_row;
end;
$$;


-- ── 5. Permisos ───────────────────────────────────────────────────────────
--
-- `create or replace` conserva los permisos existentes, pero el DROP de
-- request_admin_action se los llevó — hay que rehacerlos. cancel es nueva.

revoke all on function public.request_admin_action(text, uuid, text) from public;
revoke all on function public.request_admin_action(text, uuid, text) from anon;
grant execute on function public.request_admin_action(text, uuid, text) to authenticated;

revoke all on function public.cancel_admin_action(uuid, text) from public;
revoke all on function public.cancel_admin_action(uuid, text) from anon;
grant execute on function public.cancel_admin_action(uuid, text) to authenticated;


-- ── 6. Aviso por correo ───────────────────────────────────────────────────
--
-- Dos momentos, no uno:
--   · se PROPONE un cambio de rol → aviso temprano
--   · se EJECUTA (alguien es admin de verdad ahora) → el que importa
--
-- El valor de seguridad está en que si te llega un correo de una propuesta
-- que tú no hiciste, sabes que alguien tiene tu sesión.
--
-- Reutiliza el mismo secreto que el aviso de registros
-- (`pending_signup_webhook_secret`) para no obligar a crear otro. La Edge
-- Function lo compara igual.

create or replace function public.notify_admin_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_secret text;
  event_name text;
  target_email text;
  target_name text;
  actor_email text;
  actor_name text;
begin
  if tg_op = 'INSERT' then
    event_name := 'requested';
  elsif new.status = 'executed' and old.status is distinct from 'executed' then
    event_name := 'executed';
  else
    return new;
  end if;

  begin
    select pac.config_value
    into webhook_secret
    from public.private_app_config pac
    where pac.config_key = 'pending_signup_webhook_secret'
    limit 1;

    if webhook_secret is null or webhook_secret = '' then
      raise notice 'admin action notification skipped: missing webhook secret';
      return new;
    end if;

    -- Un correo con dos UUID no le sirve a nadie. La resolución de nombres se
    -- hace aquí, que es donde hay permiso (security definer), y no en la Edge
    -- Function — que necesitaría una credencial elevada propia para lograr lo
    -- mismo. Menos secretos circulando.
    select p.email, p.display_name into target_email, target_name
    from public.profiles p where p.user_id = new.target_user_id;

    select p.email, p.display_name into actor_email, actor_name
    from public.profiles p where p.user_id = new.created_by;

    perform net.http_post(
      url := 'https://dqjjxxqruxxfsfoejdzl.supabase.co/functions/v1/notify-admin-action',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-webhook-secret', webhook_secret
      ),
      body := jsonb_build_object(
        'event', event_name,
        'record', to_jsonb(new),
        'target', jsonb_build_object('email', target_email, 'display_name', target_name),
        'actor', jsonb_build_object('email', actor_email, 'display_name', actor_name)
      )
    );
  exception
    -- El aviso NUNCA debe tumbar un cambio de rol: si falla, se anota y sigue.
    -- Misma lección que el aviso de registros nuevos.
    when others then
      raise notice 'admin action notification skipped: %', sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists admin_actions_notify on public.admin_actions;
create trigger admin_actions_notify
after insert or update of status on public.admin_actions
for each row
execute function public.notify_admin_action();

commit;
