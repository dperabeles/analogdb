-- touch_mobile_seen(): por fin alguien escribe last_mobile_seen_at
--
-- Las columnas `last_mobile_seen_at` y `last_mobile_version` existen desde
-- hace meses y están en NULL para los 21 usuarios, porque NADA las escribía.
-- La migración de admin_behavior_stats ya lo dejó anotado: "si algún día se
-- cablea, esta función es el sitio".
--
-- Importa más de lo que parece. Sin esto solo se puede medir quién CARGA
-- rollos, y eso confunde dos cosas distintas: "no le interesó" y "no se
-- acordó de entrar". Son problemas opuestos —uno se arregla con producto, el
-- otro con un recordatorio— y hasta hoy no había forma de distinguirlos.
--
-- security definer y campo por campo: el usuario no puede tocar su propio
-- `status` ni su rol de rebote. Solo sella que estuvo aquí.
create or replace function public.touch_mobile_seen(p_version text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;   -- sin sesión no hay nada que sellar, y tampoco es un error
  end if;

  update public.profiles
     set last_mobile_seen_at = now(),
         -- La versión solo se pisa si viene: así una llamada sin argumento no
         -- borra el dato que ya había.
         last_mobile_version = coalesce(nullif(btrim(p_version), ''), last_mobile_version)
   where user_id = auth.uid();
end $$;

revoke all on function public.touch_mobile_seen(text) from public, anon;
grant execute on function public.touch_mobile_seen(text) to authenticated;
