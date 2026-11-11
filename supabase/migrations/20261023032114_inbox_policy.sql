-- Buzón privado (ANA-185): el aviso de cambios en la política (DEC-014).
--
-- Lo publica un administrador, en español y en inglés, con la fecha en que
-- entra en vigor: al menos 5 días después del día de publicación, que es lo
-- que prometen la privacidad §16, los términos §22 y las cookies §11. Llega a
-- cada cuenta creada antes de publicarlo, activada o no; una cuenta nueva
-- acepta la política vigente al registrarse. No se edita: corregirla es
-- publicar otra. Va arriba del buzón hasta que se abre, y la primera apertura
-- queda guardada como prueba del aviso.

create function public.inbox_publish_policy(p_title_es text, p_title_en text, p_summary_es text,
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

  return v_id;
end;
$$;

revoke all on function public.inbox_publish_policy(text, text, text, text, text, date) from public, anon;
grant execute on function public.inbox_publish_policy(text, text, text, text, text, date) to authenticated;
