# Aviso de Privacidad — Analog Archive

**Última actualización:** 24 de mayo de 2026
**Idioma de referencia:** Español (México) — versión en inglés disponible bajo petición.

---

## 1 · Quiénes somos

**Analog Archive** ("la aplicación", "el servicio", "nosotros") es una bitácora privada de fotografía analógica operada por **Diego Perabeles**, persona física con actividad empresarial, desde Monterrey, Nuevo León, México, bajo el nombre comercial **Analog Archive**. La aplicación está disponible vía sitio web (`https://analog-archive.com`) y como aplicación móvil para iOS y Android.

Si tienes preguntas sobre este aviso o sobre cómo manejamos tus datos, puedes escribirnos a:

- **Email legal/privacidad:** legal@analog-archive.com
- **Soporte general:** hello@analog-archive.com
- **Sitio web:** https://analog-archive.com

---

## 2 · Qué datos recolectamos

### 2.1 · Datos de cuenta

- **Correo electrónico** (obligatorio)
- **Contraseña** (almacenada cifrada con hashing irreversible — nunca en texto plano)
- **Nombre o alias público** (opcional)
- **Identificadores de proveedores sociales** cuando vinculas Sign in with Apple o Sign in with Google: un ID anónimo emitido por Apple o Google. Si autorizas, también recibimos tu nombre y correo verificado del proveedor.

### 2.2 · Datos de perfil

- **Estado de aprobación** (`pendiente`, `aprobado`, `rechazado`) — Analog Archive opera bajo beta privada con aprobación manual durante la fase actual del producto.
- **Rol** (usuario regular, administrador, founder)
- **Fecha de registro y última actividad**
- **Preferencias de notificaciones** (push, email reminders, etc.)

### 2.3 · Contenido que tú creas

Los datos que ingresas voluntariamente al catalogar tus rollos de fotografía:

- **Rollos:** stock de película, formato físico (35mm, 120, Super 8, 16mm, 110, Large Format), ISO, fechas (cargado, expuesto, enviado a revelar, revelado), push/pull, rating, notas, locaciones (texto libre, no GPS), tipos de fotografía, tags
- **Cámaras:** fabricante, modelo, formato soportado, fecha de adquisición
- **Lentes:** montura, distancia focal, apertura máxima
- **Ajustes por fotograma:** apertura, velocidad, indicadores de flash/blanco-y-negro/trípode, notas por frame (hasta 36 por rollo)
- **Contribuciones a catálogos comunitarios:** entradas que agregues a los catálogos compartidos de stocks de película y laboratorios (`film_stocks`, `labs`)

### 2.4 · Datos del dispositivo (solo app móvil)

- **Token de Firebase Cloud Messaging (FCM)** — identificador opaco para enviarte notificaciones push
- **Plataforma** (iOS o Android)
- **Versión de la app** instalada
- **Idioma del sistema** (para localización futura)

### 2.5 · Datos de uso y errores

- **Reportes de errores anonimizados** vía Sentry — stack traces, versión de la app, modelo de dispositivo, idioma. No incluyen tu contenido ni identificadores personales.
- **Logs de autenticación** (intentos de login fallidos, IP de origen) para protección contra ataques de fuerza bruta. Se guardan por un máximo de 30 días.
- **Identificadores de transacción** (cuando el servicio sea de pago en el futuro: Apple App Store IAP transaction ID, Google Play Order ID. **Nunca recibimos información de tarjeta de crédito** — Apple/Google la manejan internamente.)

### 2.6 · Datos que NO recolectamos

- **No usamos IDFA** ni identificadores de tracking entre apps (App Tracking Transparency en iOS).
- **No instalamos cookies de terceros** para publicidad o analytics cross-site en la versión web.
- **No tenemos acceso a tu galería de fotos** en la versión móvil (la app no permite subir imágenes en su versión actual).
- **No recolectamos datos biométricos** (Face ID y Touch ID los maneja iOS directamente para autenticación; no los recibimos).
- **No usamos Google Analytics, Mixpanel, Amplitude, PostHog ni ninguna herramienta de analytics de tracking** en la versión actual.
- **No tenemos Facebook Pixel, Google Ads tag, ni pixels de marketing**.
- **No recolectamos geolocalización GPS** del dispositivo. Las "locaciones" en rollos son texto libre que tú escribes, no coordenadas.
- **No vendemos datos a anunciantes ni a brokers de información.**

---

## 3 · Dónde guardamos tus datos

| Servicio | Propósito | Ubicación |
|---|---|---|
| **Supabase** (PostgreSQL + Auth + Storage) | Base de datos principal, autenticación, sesiones | AWS us-east-1 (Virginia, EE.UU.) |
| **Sentry** | Reportes de errores anonimizados | Estados Unidos |
| **Vercel** | Hosting del sitio web `analog-archive.com` | Red global con caché regional, primary US |
| **Firebase Cloud Messaging** (Google) | Entrega de notificaciones push a tu dispositivo | Infraestructura global de Google |
| **Apple Push Notification Service** | Entrega de push a iOS (vía FCM) | Infraestructura de Apple |
| **Resend** | Envío de correos transaccionales (aprobación, password reset) | Estados Unidos |

Todos los servicios usan cifrado **TLS 1.2+** en tránsito y **cifrado AES-256 en reposo**. Tus contraseñas se almacenan con hashing **bcrypt** irreversible.

---

## 4 · Con quién compartimos tus datos

Compartimos datos limitados con los siguientes **proveedores de servicio** (procesadores bajo GDPR Art. 28 / equivalentes), estrictamente necesarios para operar el servicio:

- **Supabase** — almacenamiento de todos tus datos en la base de datos principal
- **Sentry** — recibe reportes de error anonimizados, sin tu contenido
- **Firebase Cloud Messaging (Google)** — recibe tu token FCM y el payload de las notificaciones push
- **Apple Push Notification Service** — recibe payloads de push para entrega en iOS (vía FCM)
- **Resend** — provider de correo transaccional. Recibe tu email y el contenido del correo (aprobación, password reset)
- **Vercel** — hosting del sitio web. Recibe requests HTTP de tu navegador
- **Apple** — solo cuando usas Sign in with Apple. Apple recibe que abriste sesión en Analog Archive y nos devuelve un identificador anónimo. Nosotros no compartimos tu contenido con Apple
- **Google** — solo cuando usas Sign in with Google. Aplican las mismas restricciones

Todos estos proveedores tienen **Data Processing Agreements (DPAs)** con Standard Contractual Clauses (SCCs) aprobadas por la Comisión Europea para transferencias internacionales (ver sección 11).

**Nunca compartimos:**

- Tu contenido (rollos, cámaras, notas, exposiciones) con terceros para fines distintos a operar el servicio
- Tu información con anunciantes, brokers o redes de publicidad
- Tus datos con redes sociales para perfilamiento o targeting
- Tus datos con autoridades, excepto si recibimos una orden legal válida bajo jurisdicción mexicana o aplicable

---

## 5 · Cuánto tiempo guardamos tus datos

- **Cuenta activa:** mientras tu cuenta exista
- **Cuenta eliminada por el usuario:** purgada del sistema en un máximo de **30 días**. Aportes a catálogos compartidos (`film_stocks`, `labs`) se **anonimizan** pero permanecen disponibles para otros usuarios.
- **Cuenta inactiva por más de 24 meses:** te enviamos un aviso por correo. Si no respondes en 90 días, la cuenta se marca como inactiva y se purga en los siguientes 30 días.
- **Logs de autenticación:** 30 días máximo
- **Reportes de Sentry:** 90 días máximo
- **Backups:** respaldos diarios por 30 días + respaldos mensuales por 12 meses, en infraestructura cifrada de Supabase

---

## 6 · Tus derechos sobre tus datos

Bajo la **Ley Federal de Protección de Datos Personales en Posesión de los Particulares (LFPDPPP)** de México y prácticas internacionales (GDPR, CCPA, etc.), tienes los siguientes derechos:

### 6.1 · Acceder a tus datos
Desde la app móvil o web: `Cuenta → Exportar → Descargar JSON`. Recibes un archivo con todos tus rollos, cámaras, lentes, exposiciones y metadata.

### 6.2 · Corregir tus datos
Cualquier campo es editable en cualquier momento desde la app.

### 6.3 · Eliminar tu cuenta
Desde la app móvil o web: `Cuenta → Eliminar cuenta`. La operación es **irreversible**. Se purgan:

- Todos tus rollos, cámaras, lentes, exposiciones, notas, tags
- Tu perfil y credenciales
- Tu vinculación con Apple/Google (no afecta tu cuenta en esos servicios)
- Tu token FCM (dejas de recibir push)

Lo que **NO se borra automáticamente** y debes contactarnos para gestionar:

- Aportes a catálogos compartidos (`film_stocks` y `labs` que creaste y otros usuarios usan) — se anonimizan pero se mantienen disponibles. Si quieres eliminar también esos aportes, escríbenos a `legal@analog-archive.com`.

### 6.4 · Limitar el uso de tus datos
Puedes desactivar push notifications desde la configuración del sistema (iOS/Android) o desde `Cuenta → Notificaciones`.

### 6.5 · Portabilidad
La exportación JSON está diseñada como estructura legible (no propietaria) para que puedas migrar a otra herramienta si así lo decides.

### 6.6 · Revocar consentimiento
Cerrar sesión o eliminar la cuenta revoca todo procesamiento futuro. Procesamiento previo bajo consentimiento permanece válido.

### 6.7 · No discriminación
No te discriminaremos (rechazo de servicio, precios distintos, calidad degradada) por ejercer cualquiera de estos derechos.

Para ejercer cualquiera de estos derechos puedes hacerlo directamente desde la app o escribirnos a **legal@analog-archive.com** con el asunto `[PRIVACIDAD]`. Respondemos dentro de **20 días hábiles** conforme al Artículo 32 de la LFPDPPP.

---

## 7 · Sign in with Apple — nota específica

Si usas Sign in with Apple, Apple te ofrece la opción de **ocultar tu correo real** (relay anonimizado tipo `xxxx@privaterelay.appleid.com`). Respetamos esa decisión: solo verás el correo enmascarado en tu perfil. Todas las comunicaciones siguen funcionando porque Apple relaya los correos a tu dirección real sin que nosotros la conozcamos.

Si más tarde desvinculas tu Apple ID en `Cuenta → Métodos de acceso`, mantendrás tu cuenta activa siempre y cuando tengas al menos un método de acceso configurado (correo + password u otra identidad social).

---

## 8 · Niños y menores

Analog Archive **no está dirigido a menores de 13 años** y no recolectamos datos a sabiendas de niños menores de esa edad. Si descubres que un menor ha creado una cuenta, escríbenos a `legal@analog-archive.com` y la eliminaremos.

No usamos lenguaje, diseño visual ni marketing dirigido a menores. No tenemos features específicas para niños.

---

## 9 · Derechos específicos por jurisdicción

Esta sección complementa los derechos generales de la sección 6 con disposiciones específicas de jurisdicciones internacionales.

### 9.1 · Unión Europea, Reino Unido, Suiza, Noruega, Islandia, Liechtenstein (GDPR / FADP)

Bajo el **Reglamento General de Protección de Datos (GDPR)** y leyes equivalentes, tienes derecho a:

- Acceso a tus datos (Art. 15)
- Rectificación (Art. 16)
- Eliminación / derecho al olvido (Art. 17)
- Limitación del tratamiento (Art. 18)
- Portabilidad (Art. 20)
- Oposición al tratamiento (Art. 21)
- No ser sujeto de decisiones automatizadas con efectos legales significativos (Art. 22) — **no hacemos profiling automatizado**
- Presentar quejas ante la autoridad de protección de datos competente en tu país

**Base legal para el tratamiento:**

- **Performance of contract (Art. 6(1)(b)):** procesar tus datos para entregar el servicio que aceptaste al registrarte
- **Legitimate interest (Art. 6(1)(f)):** seguridad anti-fraude, debugging vía Sentry, moderación de catálogos comunitarios, gestión de aprobación beta
- **Consent (Art. 6(1)(a)):** vinculación opcional con Apple/Google, suscripción a comunicaciones de feedback

### 9.2 · California (CCPA / CPRA)

Bajo la **California Consumer Privacy Act** y **California Privacy Rights Act**, tienes derecho a:

- Saber qué información personal hemos recolectado (right to know)
- Eliminar tu información personal (right to delete)
- Corregir información inexacta (right to correct)
- Opt-out de la venta o sharing de información — **no vendemos ni compartimos información para publicidad cross-context**
- Limitar el uso de sensitive personal information — **no colectamos sensitive PI**
- No discriminación por ejercer estos derechos
- Designar un agente autorizado para ejercer estos derechos en tu nombre

**Categorías de información personal recolectada bajo CCPA Section 1798.140(o):**

- **Identifiers** (Section 1798.140(o)(1)(A)): email, nombre/alias, Apple ID, Google account ID, IP, FCM token, user UUID
- **California Customer Records** (Section 1798.80): nombre (cuando lo proporcionas)
- **Internet/network activity:** información de uso de la app (anonimizada vía Sentry)
- **Geolocation:** NO (no recolectamos geolocation precisa)
- **Sensory information:** NO
- **Professional/employment info:** NO
- **Education info:** NO
- **Inferences:** NO (no hacemos profiling)

Para ejercer derechos CCPA: `https://analog-archive.com/contact` o `legal@analog-archive.com`. Right to appeal: mismo correo con asunto `[APELACIÓN]`.

**California Shine the Light Law (Civil Code §1798.83):** los residentes de California pueden solicitar información sobre divulgaciones a terceros para fines de marketing directo. **No divulgamos información para marketing directo de terceros**, pero puedes solicitar confirmación formal escribiendo a `legal@analog-archive.com`.

### 9.3 · Otras leyes estatales de EE.UU.

Si resides en cualquiera de los siguientes estados, **tienes derechos sustancialmente similares a CCPA** bajo la legislación local. Los derechos se ejercen mediante los mismos mecanismos descritos en sección 6:

- Virginia (VCDPA)
- Colorado (CPA)
- Connecticut (CTDPA)
- Utah (UCPA)
- Texas (TDPSA)
- Oregon (OCPA)
- Montana (MCDPA)
- Iowa (ICDPA)
- Tennessee (TIPA)
- Indiana (ICDPA)
- New Jersey (NJDPA)
- Delaware (DPDPA)
- New Hampshire (NHPA)
- Maryland (MODPA)
- Minnesota (MCDPA)
- Rhode Island (RIDTPPA)
- Florida (FDBR)
- Kentucky (KCDPA)
- Nebraska (NDPA)

Para Texas, Florida y Nebraska específicamente, ofrecemos al menos dos métodos para enviar solicitudes de privacidad: `legal@analog-archive.com` y `https://analog-archive.com/contact`.

### 9.4 · Canadá (PIPEDA y Quebec Law 25)

Bajo la **Personal Information Protection and Electronic Documents Act (PIPEDA)** y la **Law 25 de Quebec**, tienes derecho a:

- Acceso a tu información personal
- Corrección de información inexacta
- Retirar consentimiento
- Presentar quejas ante el Office of the Privacy Commissioner of Canada o la Commission d'accès à l'information du Québec

### 9.5 · Otras jurisdicciones globales

Esta política también cumple con:

- **POPIA** (Protection of Personal Information Act — Sudáfrica)
- **Privacy Act 1988** y **Australian Privacy Principles** (Australia)
- **The Privacy Act 2020** (Nueva Zelanda)

Si resides en estas jurisdicciones, los derechos generales descritos en sección 6 aplican, complementados por las protecciones específicas de tu legislación local. Para ejercerlos, contacta `legal@analog-archive.com`.

---

## 10 · Data Protection Officer / Responsable de privacidad

**Designamos como responsable de privacidad y contacto de protección de datos:**

- **Nombre:** Diego Perabeles
- **Cargo:** Operator and Data Protection Contact
- **Email:** legal@analog-archive.com
- **Domicilio:** Monterrey, Nuevo León, México

Aunque legalmente no estamos obligados bajo GDPR Art. 37 a tener un DPO formal (no somos autoridad pública, no hacemos monitoreo a gran escala, no procesamos sensitive data a gran escala), designamos voluntariamente un contacto único de protección de datos como muestra de compromiso con la privacidad de nuestros usuarios.

---

## 11 · Transferencias internacionales de datos

Como nuestros servidores principales están en **Estados Unidos** (vía Supabase, Sentry, Firebase, Resend, Vercel), tus datos pueden ser transferidos y almacenados fuera de tu país de residencia.

### 11.1 · Mecanismos legales de transferencia

Estas transferencias se realizan bajo los siguientes mecanismos válidos:

- **Standard Contractual Clauses (SCCs)** aprobadas por la Comisión Europea — incluidas en todos los Data Processing Agreements con nuestros proveedores
- **EU-US Data Privacy Framework (DPF)** — varios de nuestros proveedores (Supabase, Sentry, Google/Firebase, Vercel) están certificados bajo DPF
- **Article 36 LFPDPPP** (México) — reconoce SCCs como mecanismo válido para transferencias internacionales

### 11.2 · Países destino

- **Estados Unidos** (servidores primarios de todos los proveedores)
- Edge servers globales (solo para entrega de contenido estático, sin almacenamiento de data personal)

### 11.3 · Solicitud de copias de SCCs

Si quieres una copia de los SCCs aplicables a tu jurisdicción, escríbenos a `legal@analog-archive.com` con el asunto `[SCCs REQUEST]`.

---

## 12 · Solicitudes de acceso del titular (DSARs)

Ofrecemos **múltiples mecanismos** para que ejerzas tus derechos sobre tus datos personales:

### 12.1 · Mecanismos disponibles

| Mecanismo | Cuándo usarlo |
|---|---|
| **Botón in-app** `Cuenta → Exportar` | Descargar JSON con todos tus datos (right to access + portability) |
| **Botón in-app** `Cuenta → Eliminar cuenta` | Eliminación irreversible (right to delete) |
| **Edición in-app** de cualquier campo | Corrección de datos (right to correct) |
| **Correo a legal@analog-archive.com** | Solicitudes complejas, apelaciones, jurisdicciones específicas |
| **Contact form** en `https://analog-archive.com/contact` | Alternativa por web con dropdown de tipo de solicitud |

### 12.2 · Tiempos de respuesta

- **Solicitudes simples** (vía botones in-app): inmediatas
- **Solicitudes por correo:** respondemos dentro de **20 días hábiles** (conforme LFPDPPP Art. 32)
- **Solicitudes GDPR:** dentro de **1 mes** (Art. 12(3) GDPR)
- **Solicitudes CCPA:** dentro de **45 días** (extensible a 90 días en casos complejos con aviso)

### 12.3 · Verificación de identidad

Para proteger contra solicitudes fraudulentas, verificamos tu identidad antes de procesar solicitudes sensibles. Para usuarios autenticados, esto es automático (estás logueado). Para solicitudes por correo desde el correo de tu cuenta, se considera verificación suficiente. Si solicitas desde otro correo, podemos pedir información adicional.

### 12.4 · Derecho de apelación

Si rechazamos tu solicitud (ej. porque no podemos verificarte, porque la solicitud está fuera de scope, o porque entra en conflicto con derechos de terceros), tienes derecho a apelar. Envía un correo a `legal@analog-archive.com` con el asunto `[APELACIÓN]` y reconsideraremos.

---

## 13 · Cookies y tecnologías similares

El servicio usa cookies estrictamente necesarias en la versión web (`analog-archive.com`) y tokens seguros en las apps móviles (no cookies HTTP).

**No usamos cookies de marketing, analytics, ni tracking entre sitios.**

Detalles completos en nuestra [Política de Cookies](./cookie-policy.md).

---

## 14 · Seguridad de tus datos

Implementamos múltiples capas de seguridad para proteger tu información:

- **Cifrado en tránsito:** TLS 1.2+ en todas las conexiones
- **Cifrado en reposo:** AES-256 automático en Supabase
- **Hashing de passwords:** bcrypt irreversible (no hay forma de recuperar password en plain text)
- **Row Level Security (RLS):** a nivel de base de datos — solo puedes leer/escribir tus propios datos
- **Auth gating:** JWT tokens con expiración automática
- **Anti brute-force:** rate limiting + IP logging por 30 días
- **Aprobación manual de signups** durante beta
- **Secrets management:** service role keys solo en server-side, nunca expuestas al cliente
- **Backups automáticos:** diarios (30 días) + mensuales (12 meses)

### 14.1 · Notificación de incidentes de seguridad

Si ocurre un incidente de seguridad que afecte tus datos personales, te notificaremos sin demora indebida conforme a los plazos legales aplicables:

- **GDPR/UK GDPR:** dentro de 72 horas a la autoridad + a usuarios si hay riesgo alto
- **CCPA/state laws:** sin demora razonable
- **LFPDPPP:** sin demora cuando la vulneración afecte significativamente derechos del titular

---

## 15 · Cumplimiento con la LFPDPPP (México)

Para usuarios residentes en los **Estados Unidos Mexicanos**, este Aviso de Privacidad cumple adicionalmente con la **Ley Federal de Protección de Datos Personales en Posesión de los Particulares (LFPDPPP)** y su Reglamento.

### 15.1 · Responsable del tratamiento

**Diego Perabeles**, persona física con actividad empresarial, domiciliado en Monterrey, Nuevo León, México.

### 15.2 · Datos de contacto del responsable

- **Correo legal:** legal@analog-archive.com
- **Correo de soporte:** hello@analog-archive.com
- **Sitio web:** https://analog-archive.com

### 15.3 · Finalidades del tratamiento

Los datos personales que recolectamos se utilizan para:

1. Prestar y mantener el servicio de bitácora privada de fotografía analógica
2. Autenticar tu acceso y proteger tu cuenta
3. Enviarte comunicaciones operacionales relacionadas con el servicio (aprobación de cuenta, recordatorios funcionales, notificaciones de cambios)
4. Responder a tus solicitudes y consultas
5. Prevenir fraude, abuso y mantener la seguridad del servicio
6. Cumplir con obligaciones legales aplicables

**Finalidades secundarias** (que requieren tu consentimiento expreso si decides participar):

- Solicitud de feedback durante la fase beta para mejorar el producto

### 15.4 · Derechos ARCO

Como titular de los datos, tienes derecho a **Acceder, Rectificar, Cancelar u Oponerte** al tratamiento de tus datos personales (derechos ARCO), así como a **revocar el consentimiento** otorgado. Puedes ejercer estos derechos:

- Directamente desde la sección "Cuenta" de la aplicación (exportación, edición y eliminación de cuenta)
- Mediante solicitud por escrito a `legal@analog-archive.com`

Responderemos dentro de un plazo máximo de **20 días hábiles** conforme al Artículo 32 de la LFPDPPP.

### 15.5 · Autoridad reguladora

El **Instituto Nacional de Transparencia, Acceso a la Información y Protección de Datos Personales (INAI)** es la autoridad responsable de vigilar el cumplimiento de la LFPDPPP en México. Si consideras que tu derecho de protección de datos personales ha sido vulnerado, puedes acudir al INAI:

- **Web:** https://home.inai.org.mx
- **Teléfono INAI:** (55) 5004 2400 / 800 835 4324

### 15.6 · Transferencias internacionales bajo LFPDPPP

Tus datos pueden ser transferidos a Estados Unidos conforme al **Artículo 36 de la LFPDPPP**, bajo amparo de las Standard Contractual Clauses incluidas en los Data Processing Agreements con nuestros proveedores. Más detalle en sección 11.

### 15.7 · Cambios al aviso

Cualquier modificación material a este Aviso de Privacidad será notificada mediante correo electrónico a la dirección registrada en tu cuenta y mediante banner en la aplicación durante al menos **30 días**.

---

## 16 · Cambios a este aviso

Si modificamos este aviso de manera material, te notificaremos:

- **Por correo electrónico** a la dirección registrada en tu cuenta
- **Con un banner visible** dentro de la app y en el sitio web durante al menos **30 días** antes de la fecha efectiva del cambio

Tu uso continuado del servicio después de la fecha efectiva constituye aceptación del aviso modificado. Si no estás de acuerdo, puedes exportar tus datos y eliminar tu cuenta antes de esa fecha.

Cambios menores (correcciones tipográficas, aclaraciones, actualizaciones de URLs de proveedores) se publicarán en este documento sin notificación adicional.

---

## 17 · Jurisdicción

Este aviso se rige por las leyes de los **Estados Unidos Mexicanos**. Cualquier disputa será resuelta en los tribunales competentes de **Monterrey, Nuevo León, México**, salvo que la legislación aplicable disponga lo contrario por tu jurisdicción de residencia (GDPR, CCPA, LGPD, PIPEDA, según aplique). Los usuarios consumidores mexicanos conservan su derecho de presentar quejas ante PROFECO o el INAI según corresponda.

---

## 18 · Idioma

Este Aviso de Privacidad está disponible en **español de México** como idioma de referencia. La versión en inglés (cuando esté disponible) se considera traducción de cortesía. **En caso de conflicto interpretativo, prevalecerá la versión en español.**

---

## 19 · Documentos relacionados

- [Términos de Servicio](./terms-of-service.md) — reglas generales de uso del servicio
- [Política de Cookies](./cookie-policy.md) — uso detallado de cookies en la web

---

## 20 · Contacto

**Responsable del tratamiento:** Diego Perabeles (persona física con actividad empresarial)
**Nombre comercial / DBA:** Analog Archive
**Domicilio:** Monterrey, Nuevo León, México
**Correo legal/privacidad:** legal@analog-archive.com
**Correo de soporte general:** hello@analog-archive.com
**Sitio web:** https://analog-archive.com

### Cómo escribirnos según el tema

| Tema | Correo | Asunto sugerido |
|---|---|---|
| Privacidad y datos personales | legal@analog-archive.com | `[PRIVACIDAD]` |
| Solicitud de eliminación de cuenta | legal@analog-archive.com | `[ELIMINACIÓN]` |
| Solicitud de exportación de datos | legal@analog-archive.com | `[EXPORTACIÓN]` |
| Apelación de solicitud rechazada | legal@analog-archive.com | `[APELACIÓN]` |
| Reportes de copyright | legal@analog-archive.com | `[COPYRIGHT]` |
| Disputas legales | legal@analog-archive.com | `[DISPUTA]` |
| Solicitud de copia de SCCs | legal@analog-archive.com | `[SCCs REQUEST]` |
| Reporte de incidente de seguridad | legal@analog-archive.com | `[SEGURIDAD]` |
| Soporte técnico, dudas generales | hello@analog-archive.com | `[SOPORTE]` |

Respondemos comunicaciones legales y de privacidad dentro de **20 días hábiles** conforme al Artículo 32 de la LFPDPPP.

---

*Este aviso no constituye asesoría legal personalizada. Te recomendamos consultar con un abogado si tienes dudas específicas sobre cómo aplican estas disposiciones a tu situación particular.*

*Última revisión: 24 de mayo de 2026.*
