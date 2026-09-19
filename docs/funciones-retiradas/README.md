# Funciones Edge retiradas

Código de Edge Functions que estuvieron desplegadas y **ya no lo están**. Se
guarda aquí, y no en `supabase/functions/`, a propósito: `supabase functions
deploy` despliega todo lo que encuentre en ese directorio, así que dejar ahí una
función retirada la volvería a poner en línea en el siguiente despliegue.

Extensión `.ts.retirada` para que ninguna herramienta la tome por código vivo.

---

## `request-beta-access` — retirada el 2026-09-19

**Qué hacía.** Creaba cuentas de usuario reales llamando a
`POST /auth/v1/admin/users` con `SUPABASE_SERVICE_ROLE_KEY`, tomando correo,
contraseña y nombre del cuerpo de la petición, con `email_confirm: true` — es
decir, cuentas confirmadas **sin verificación de correo**.

**Cuándo.** Desplegada el 2026-04-26, una semana después de crear el proyecto.
**Nunca se commiteó**: los commits de esos días (`Harden beta access controls`,
`Notify users when beta access is approved`) tocan el dashboard y las
migraciones, pero ninguno añadió esta función. Se subió a mano.

**Para qué sirvió.** Fue la vía de alta de la beta. De las 21 cuentas de la
base, **18 tienen su huella** (confirmadas al crear, sin correo de confirmación
enviado), creadas entre el 26 de abril y el 9 de mayo de 2026. No era código
muerto: construyó la base de usuarios.

**Por qué se retiró.** Al auditarla el 2026-09-18:

- `verify_jwt` apagado — comprobado con un `GET` sin credenciales, que devolvía
  el `405 method_not_allowed` **de la función**, no un `401` de la puerta;
- `Access-Control-Allow-Origin: "*"` — invocable desde cualquier web;
- sin límite de peticiones, sin CAPTCHA, sin secreto compartido.

O sea: **cualquiera en internet podía crear cuentas confirmadas, sin límite.**
Y encender `verify_jwt` no lo habría arreglado, porque la clave `anon` es
pública (va dentro de la app) y es en sí misma un JWT válido.

No es una fuga: la RLS confina a cada cuenta nueva a sus propios datos. El daño
era de abuso e integridad — inundar el catálogo compartido de labs y la cola de
moderación, disparar un correo a Diego por alta, y falsear las métricas.

**Por qué era seguro retirarla.** Cero referencias en `analogdb` y en
`analogdb-mobile`; la app usa el registro normal de Supabase desde entonces; y
ninguna cuenta con su huella se creó desde el 2026-05-09 — cuatro meses.

**Si algún día hace falta algo parecido**, no reviviendo esto: una función con
`verify_jwt`, un secreto compartido como las tres de `notify-*`, límite de
peticiones, CORS acotado al dominio propio, y **sin** `email_confirm: true` —
la verificación de correo es justo lo que no se debe saltar (ver ANA-114).
