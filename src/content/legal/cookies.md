# Política de Cookies — Analog Archive

**Última actualización:** 24 de mayo de 2026
**Idioma de referencia:** Español (México) — versión en inglés disponible bajo petición.

---

## 1 · Introducción

Esta Política de Cookies explica cómo **Analog Archive** ("la aplicación", "el servicio", "nosotros") utiliza cookies y tecnologías similares en su sitio web `https://analog-archive.com` y aplicaciones móviles para iOS y Android.

El servicio es operado por **Diego Perabeles**, persona física con actividad empresarial, desde Monterrey, Nuevo León, México, bajo el nombre comercial **Analog Archive**.

Esta política es complementaria a nuestro [Aviso de Privacidad](./privacy-policy.md) y a nuestros [Términos de Servicio](./terms-of-service.md). Al usar el servicio, aceptas el uso de cookies conforme a esta política.

---

## 2 · Qué son las cookies

Las **cookies** son pequeños archivos de texto que se almacenan en tu navegador o dispositivo cuando visitas un sitio web. Permiten que el sitio recuerde información sobre tu visita, como tu sesión autenticada o preferencias.

Las **tecnologías similares** incluyen:

- **Local Storage** y **Session Storage** del navegador
- **IndexedDB** para almacenamiento estructurado
- **Web beacons** y **pixels** (que NO usamos en Analog Archive)
- **Tokens de autenticación** almacenados de forma segura

---

## 3 · Compromiso de Analog Archive con la privacidad

Antes de listar qué cookies usamos, queremos dejar claro lo que **NO hacemos**:

| Práctica | ¿Analog Archive lo hace? |
|---|---|
| **Cookies de marketing o publicidad** | ❌ No usamos ninguna |
| **Cookies de tracking entre sitios (cross-site tracking)** | ❌ No |
| **Web beacons / pixels** (Facebook Pixel, Google Ads tag, etc.) | ❌ No |
| **Google Analytics o herramientas de analytics de tracking** | ❌ No en la versión actual |
| **Cookies de redes sociales para perfilamiento** | ❌ No |
| **IDFA (Identifier for Advertisers) en iOS** | ❌ No usamos App Tracking Transparency porque no trackeamos |
| **Venta o intercambio de datos de cookies a terceros** | ❌ Nunca |

**Las únicas cookies que usamos son las estrictamente necesarias para que el servicio funcione.** Si dejáramos de usar cookies, no podrías iniciar sesión ni mantener tu sesión activa entre páginas.

---

## 4 · Qué cookies usamos exactamente

A continuación listamos cada cookie específica que el servicio coloca en tu navegador cuando usas `analog-archive.com`. Las aplicaciones móviles (iOS y Android) **no usan cookies HTTP** — usan tokens seguros almacenados en el Keychain de iOS o el Keystore de Android.

### 4.1 · Cookies estrictamente necesarias (Esenciales)

Estas cookies son indispensables para el funcionamiento del servicio. **No se pueden desactivar** sin romper la funcionalidad básica.

| Cookie | Origen | Propósito | Duración | Tipo |
|---|---|---|---|---|
| `sb-access-token` | Supabase Auth (first-party) | Token JWT que mantiene tu sesión autenticada activa | Hasta logout o expiración (~1 hora, renovado automáticamente) | HTTP-only, Secure, SameSite=Lax |
| `sb-refresh-token` | Supabase Auth (first-party) | Permite renovar tu sesión sin pedirte login cada hora | Hasta logout o expiración (~30 días por defecto) | HTTP-only, Secure, SameSite=Lax |
| `__cf_bm` | Cloudflare (via Supabase) | Detección de bots y protección contra ataques automatizados | 30 minutos | HTTP-only, Secure |
| `gpc-honored` | First-party | Registra que respetamos tu señal Global Privacy Control si la activaste | 1 año | HTTP-only, Secure, SameSite=Lax |

### 4.2 · Cookies de Vercel (plataforma de hosting)

Vercel hostea nuestro sitio web Next.js. Puede usar cookies operacionales mínimas para enrutamiento edge y seguridad. Estas son first-party desde la perspectiva del usuario (mismo dominio `analog-archive.com`).

| Cookie | Origen | Propósito | Duración |
|---|---|---|---|
| Cookies internas de Vercel | Vercel platform | Routing edge, geo-redirect, A/B testing infrastructure (no usado activamente) | Variable, mayormente session |

### 4.3 · Cookies que NO usamos

Para ser explícitos, el servicio **NO usa**:

- ❌ Cookies de Google Analytics
- ❌ Cookies de Mixpanel, Amplitude, PostHog
- ❌ Cookies de Facebook Pixel
- ❌ Cookies de Twitter/X conversion tracking
- ❌ Cookies de LinkedIn Insight Tag
- ❌ Cookies de TikTok Pixel
- ❌ Cookies de retargeting (AdRoll, Google Ads remarketing)
- ❌ Cookies de afiliados o referencias comerciales

Si en el futuro agregamos alguna herramienta de analytics o tracking, **actualizaremos esta política** y te notificaremos conforme se describe en la sección 11 de los [Términos de Servicio](./terms-of-service.md).

---

## 5 · Cookies en aplicaciones móviles

Las aplicaciones móviles iOS y Android **no usan cookies HTTP**. En su lugar, almacenan tokens seguros en:

- **iOS:** **Keychain** del sistema (cifrado a nivel hardware, protegido por Secure Enclave)
- **Android:** **Keystore** del sistema (cifrado a nivel hardware cuando el dispositivo lo soporta)

Estos tokens cumplen la misma función que las cookies de sesión web (mantenerte autenticado) pero usan el mecanismo nativo de cada plataforma móvil, que es **más seguro** que cookies HTTP.

Adicionalmente, las apps móviles almacenan localmente:

- **Token FCM (Firebase Cloud Messaging)** — identificador opaco para entregar push notifications. Almacenado por Firebase SDK en almacenamiento de la app.
- **Cache de datos del servicio** — copias temporales de tus rollos, cámaras, etc. para mejorar performance offline. Vive en almacenamiento sandbox de la app.

Ninguno de estos elementos es accesible a otras apps en tu dispositivo, y se eliminan automáticamente cuando desinstalas la aplicación.

---

## 6 · Tus derechos sobre las cookies

### 6.1 · Configuración del navegador

Puedes controlar y/o eliminar cookies en cualquier momento desde la configuración de tu navegador. Sin embargo, **si desactivas las cookies esenciales no podrás usar el servicio** (no podrás iniciar sesión).

Instrucciones por navegador:

- **Chrome:** Configuración → Privacidad y seguridad → Cookies y otros datos de sitios
- **Firefox:** Preferencias → Privacidad y Seguridad → Cookies y datos del sitio
- **Safari (macOS):** Safari → Preferencias → Privacidad
- **Safari (iOS):** Ajustes → Safari → Bloquear cookies
- **Edge:** Configuración → Cookies y permisos de sitio
- **Brave:** Configuración → Escudos → Cookies

### 6.2 · Modo navegación privada

Si usas el modo de **navegación privada / incognito**, las cookies de sesión se eliminan automáticamente al cerrar la ventana, requiriendo que inicies sesión cada vez.

### 6.3 · Global Privacy Control (GPC)

Si tu navegador envía la señal **Global Privacy Control** (Sec-GPC: 1), la respetamos automáticamente. Aunque Analog Archive no vende ni comparte datos para publicidad (por lo que GPC no tiene mucho que apagar), registramos tu preferencia mediante una cookie `gpc-honored` para mantener consistencia entre sesiones.

### 6.4 · Eliminar cookies de Analog Archive específicamente

Puedes eliminar todas las cookies de `analog-archive.com` desde tu navegador. Esto cerrará tu sesión automáticamente — la próxima vez que visites tendrás que iniciar sesión de nuevo.

---

## 7 · Consentimiento

### 7.1 · Cookies esenciales (consentimiento implícito)

Las cookies esenciales descritas en la sección 4.1 son **estrictamente necesarias** para que el servicio funcione. Bajo el Reglamento ePrivacy de la UE (Directiva 2002/58/CE) y la mayoría de regulaciones de privacidad globales, **las cookies esenciales no requieren consentimiento previo** — son parte del funcionamiento básico que el usuario solicita al acceder al servicio.

### 7.2 · Cookies opcionales

Actualmente **no usamos cookies opcionales** (de analytics, marketing, etc.). Si en el futuro las agregamos:

- Aparecerá un **banner de consentimiento** en tu primera visita pidiendo tu autorización
- Podrás aceptar o rechazar categorías específicas
- Podrás cambiar tus preferencias en cualquier momento desde un enlace permanente en el footer del sitio

### 7.3 · No tienes que aceptar nada hoy

Como solo usamos cookies esenciales, **no necesitas tomar ninguna acción para "aceptar cookies"** al visitar `analog-archive.com`. El servicio simplemente funciona.

---

## 8 · Cookies de terceros (servicios de proveedores)

Aunque el servicio en sí no coloca cookies de terceros para marketing, **ciertos proveedores que usamos como infraestructura** pueden colocar sus propias cookies operacionales:

| Proveedor | Cuándo aplica | Propósito de su cookie | Privacy Policy |
|---|---|---|---|
| **Supabase** | Siempre (es el backend) | Auth tokens (las cookies `sb-*` listadas arriba) | https://supabase.com/privacy |
| **Cloudflare** (via Supabase) | Cuando hay tráfico sospechoso | Bot detection (`__cf_bm`) | https://www.cloudflare.com/privacypolicy/ |
| **Vercel** | Siempre (hostea el sitio) | Routing edge y operación de la plataforma | https://vercel.com/legal/privacy-policy |
| **Apple** (solo si usas Sign in with Apple) | Durante OAuth flow | Auth flow temporal de Apple | https://www.apple.com/legal/privacy/ |
| **Google** (solo si usas Sign in with Google) | Durante OAuth flow | Auth flow temporal de Google | https://policies.google.com/privacy |

Todos estos servicios actúan como **procesadores de datos** en nuestro nombre bajo Data Processing Agreements (DPAs) con cláusulas estándar contractuales (SCCs) aprobadas por la Comisión Europea. Más detalle en el [Aviso de Privacidad](./privacy-policy.md), sección 4.

---

## 9 · Niños

Esta política, como nuestro [Aviso de Privacidad](./privacy-policy.md), aplica a usuarios de **13 años o más**. No recolectamos datos a sabiendas de niños menores de esa edad.

---

## 10 · Cumplimiento con leyes aplicables

Esta política y nuestro uso de cookies cumple con:

- **LFPDPPP** (Ley Federal de Protección de Datos Personales en Posesión de los Particulares — México)
- **GDPR Article 5(3)** y **ePrivacy Directive 2002/58/CE** (Unión Europea)
- **CCPA / CPRA** (California Consumer Privacy Act / California Privacy Rights Act)
- **Otras leyes estatales de EE.UU.** (Virginia VCDPA, Colorado CPA, Connecticut CTDPA, etc.)
- **PIPEDA** (Canadá) y **Law 25** (Quebec)
- **POPIA** (Sudáfrica), **Privacy Act 1988** (Australia), **Privacy Act 2020** (Nueva Zelanda)
- **Otras regulaciones de privacidad aplicables**

---

## 11 · Cambios a esta política

Si modificamos materialmente esta Política de Cookies (por ejemplo, agregamos analytics opcionales o cualquier nueva categoría de cookies), te notificaremos:

- Por correo electrónico a la dirección registrada en tu cuenta
- Con un banner visible en el sitio web durante al menos 30 días
- Mediante actualización de la fecha en la parte superior de este documento

Cambios menores (correcciones tipográficas, aclaraciones, actualización de URLs de proveedores) se publicarán sin notificación adicional.

---

## 12 · Contacto

Si tienes preguntas sobre nuestro uso de cookies o quieres ejercer derechos relacionados:

- **Email legal/privacidad:** legal@analog-archive.com (asunto sugerido: `[COOKIES]`)
- **Soporte general:** hello@analog-archive.com
- **Sitio web:** https://analog-archive.com

Respondemos solicitudes relacionadas con privacidad y cookies dentro de **20 días hábiles** conforme al Artículo 32 de la LFPDPPP.

---

## 13 · Documentos relacionados

- [Aviso de Privacidad](./privacy-policy.md) — qué datos recolectamos, cómo los usamos
- [Términos de Servicio](./terms-of-service.md) — reglas generales de uso del servicio

---

*Esta política no constituye asesoría legal personalizada. Te recomendamos consultar con un abogado si tienes dudas específicas sobre cómo aplican estas disposiciones a tu situación.*

*Última revisión: 24 de mayo de 2026.*
