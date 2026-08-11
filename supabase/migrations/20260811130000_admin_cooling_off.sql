-- Enfriamiento de 24 h cuando el voto es efectivamente unilateral (ANA-121).
--
-- ── El problema ───────────────────────────────────────────────────────────
--
-- Con un solo admin, `proponer` + `votar` es una ceremonia de dos llamadas
-- que no protege de nada: tú propones, tú apruebas, se ejecuta. La unanimidad
-- es real pero vacía cuando el conjunto de votantes es una sola persona.
-- Quien se haga con una sesión de admin se promueve en dos llamadas.
--
-- ── El diseño, y por qué NO es el que se planteó al principio ─────────────
--
-- La idea original era "queda programada y se ejecuta sola a las 24 h". Eso
-- necesitaba `pg_cron` (disponible en el proyecto pero sin instalar) y, sobre
-- todo, es MENOS seguro: el atacante propone, aprueba, y el cambio ocurre
-- solo aunque para entonces ya haya perdido el acceso.
--
-- Lo que se implementa es: **la aprobación unilateral no ejecuta; hay que
-- volver a confirmarla pasadas 24 h**.
--
--   · Diego promoviendo a alguien de verdad → aprueba, espera un día, vuelve
--     y confirma. Fricción mínima en algo que hará casi nunca.
--   · Alguien con su sesión → propone y aprueba, y no pasa nada. Le llega el
--     correo del alta al instante y puede cancelar. Para que el ataque
--     prospere tendría que CONSERVAR el acceso 24 h y actuar dos veces.
--   · Con dos o más admins → no cambia nada: la unanimidad ya aporta la
--     segunda persona y ejecuta al momento.
--
-- Más seguro y sin infraestructura nueva. No hace falta cron.
--
-- ── Asimetría deliberada: solo aplica a PROMOVER ──────────────────────────
--
-- Degradar sigue siendo inmediato. Si sospechas que una cuenta está
-- comprometida, quieres revocarle el acceso YA, no dentro de un día. Retrasar
-- una revocación sería exactamente el error contrario.
--
-- ── Detalle fino: el reloj no se reinicia ─────────────────────────────────
--
-- El `on conflict` de los votos hacía `decided_at = now()` siempre. Con eso,
-- volver a aprobar reiniciaba las 24 h y la confirmación nunca llegaba a
-- cumplirse. Ahora solo se refresca la fecha si el voto CAMBIA de sentido.

begin;

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
  first_approval_at timestamptz;
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

  -- Caducidad: una propuesta vencida no se vota, se auto-cancela.
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

  -- El `decided_at` solo se refresca si el voto cambia de sentido. Si no,
  -- confirmar reiniciaría el enfriamiento y nunca se cumpliría.
  insert into public.admin_action_approvals (action_id, admin_user_id, decision)
  values (p_action_id, actor_id, p_decision)
  on conflict (action_id, admin_user_id)
  do update set
    decision = excluded.decision,
    decided_at = case
      when public.admin_action_approvals.decision = excluded.decision
        then public.admin_action_approvals.decided_at
      else now()
    end;

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

  -- ▼ NUEVO: enfriamiento cuando la unanimidad la firma una sola persona.
  --
  -- Solo al PROMOVER. Degradar es inmediato a propósito: revocar acceso
  -- deprisa es una propiedad deseable, retrasarlo sería el error contrario.
  if eligible_admin_count = 1 and action_row.action_type = 'promote_to_admin' then
    select min(aaa.decided_at)
    into first_approval_at
    from public.admin_action_approvals aaa
    where aaa.action_id = p_action_id
      and aaa.decision = 'approved';

    if first_approval_at is null
       or now() < first_approval_at + interval '24 hours' then
      -- Queda aprobada pero sin ejecutar. Vuelve a llamarse a esta función
      -- pasadas las 24 h para confirmar.
      return action_row;
    end if;
  end if;
  -- ▲ NUEVO

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
    resolved_reason = case
      when eligible_admin_count = 1 then 'Approved by sole admin after cooling-off'
      else 'Unanimous approval reached'
    end
  where id = p_action_id
  returning * into action_row;

  return action_row;
end;
$$;

commit;
