-- `admin_inbox()` decía "0 pendientes" cuando quería decir "no eres admin".
--
-- ── El fallo ────────────────────────────────────────────────────────────────
--
-- La función respondía a cualquiera:
--
--     if not public.app_is_admin(auth.uid()) then
--       return jsonb_build_object('total', 0, 'items', jsonb_build_object());
--     end if;
--
-- No hay fuga: devuelve vacío. El problema es que **tres situaciones distintas
-- daban la misma respuesta**:
--
--     · no eres admin
--     · eres admin y no hay nada pendiente
--     · la comprobación de admin falló
--
-- Y la tercera es la que duele. Si `app_is_admin` alguna vez devuelve false
-- para un admin de verdad —se borra su fila de `user_roles`, un `search_path`,
-- un bug— el panel diría **"0 pendientes"** en vez de dar error. Se vería la
-- bandeja vacía y se concluiría que nadie espera, mientras los labs se
-- acumulan. Es el mismo patrón que ya nos mordió cuatro veces: un verificador
-- que no distingue "no hay nada" de "no pude mirar".
--
-- ── Por qué NO se hace lanzar, que era lo obvio ─────────────────────────────
--
-- Sus tres hermanas (`admin_global_stats`, `admin_behavior_stats`,
-- `lab_usage_stats`) lanzan `admin only`, así que hacer lo mismo parecía el
-- arreglo. **Habría roto la app para 20 de los 21 usuarios.**
--
-- `adminInboxProvider` se observa en `MobShellTop` —el encabezado de TODAS las
-- pantallas— y en Cuenta. Lo observan todos, no solo los admins. Si la función
-- lanza, cada usuario normal se queda con un estado de error permanente en el
-- encabezado.
--
-- O sea: devolver vacío no era pereza, resolvía una necesidad real. Lo que
-- faltaba no era severidad, era **decir cuál de las tres cosas es**.
--
-- ── El arreglo ──────────────────────────────────────────────────────────────
--
-- Se añade `es_admin` a la respuesta. Con eso el cliente ya puede distinguir:
--
--     es_admin=false                → no eres admin (silencio, a propósito)
--     es_admin=true  + total=0      → eres admin y no hay nada
--     es_admin=false + perfil=admin → ALGO ESTÁ MAL: se avisa
--     excepción                     → falló de verdad: se avisa
--
-- Esa tercera línea es la protección: es exactamente el caso que hoy se vería
-- como "0 pendientes".
--
-- Compatible hacia atrás: `total` e `items` no cambian de forma, así que una
-- app ya instalada ignora la clave nueva y sigue funcionando igual.

create or replace function public.admin_inbox()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_labs  int;
  v_roles int;
begin
  -- No se lanza a propósito (ver arriba): se responde diciendo QUÉ pasa.
  if not public.app_is_admin(auth.uid()) then
    return jsonb_build_object(
      'total', 0,
      'items', jsonb_build_object(),
      'es_admin', false
    );
  end if;

  select count(*) into v_labs  from public.labs          where status = 'pending';
  select count(*) into v_roles from public.admin_actions where status = 'pending';

  return jsonb_build_object(
    'total', v_labs + v_roles,
    'items', jsonb_build_object(
      'labs_pending',  v_labs,
      'role_requests', v_roles
    ),
    'es_admin', true
  );
end $function$;
