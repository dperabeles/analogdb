# DPAs de proveedores

Un **DPA** (Data Processing Agreement / Acuerdo de Tratamiento de Datos) es el
contrato que obliga a un proveedor a tratar los datos personales que le pasas
solo según tus instrucciones. Lo exige el **GDPR art. 28** y, en la práctica,
es lo primero que te piden si alguna vez hay una auditoría, una solicitud de
un usuario europeo, o un cliente institucional.

La Privacy Policy ya nombra a estos proveedores como encargados del
tratamiento. Esta carpeta es donde vive la prueba de que existe el acuerdo.

## ⚠️ Esto no lo puede hacer Claude

Aceptar o firmar un DPA es **contraer una obligación legal en nombre de Analog
Archive**. Eso lo hace Diego, desde sus propias cuentas. Lo que hay aquí es el
mapa de dónde está cada uno y en qué estado.

## Estado

| Proveedor | Qué trata | Dónde se acepta / descarga | Estado |
| --- | --- | --- | --- |
| **Supabase** | Base de datos, autenticación, contenido del usuario | Dashboard → Organization → Legal Documents | ⬜ pendiente |
| **Sentry** | Reportes de error con UUID de usuario | Settings → Legal & Compliance | ⬜ pendiente |
| **Resend** | Correo transaccional (altas, recuperación, avisos) | Dashboard → Settings → Legal | ⬜ pendiente |
| **Vercel** | Alojamiento de la web, logs de petición | Dashboard → Settings → Legal → DPA | ⬜ pendiente |
| **Google / Firebase** | Push (**todavía no integrado**) | Google Cloud → Terms → Data Processing Terms | ⬜ no aplica aún |

**Firebase no aplica todavía**: la app no integra FCM (ANA-37 sigue abierto),
así que hoy no se le manda ningún dato. En cuanto entre push, ese DPA pasa a
ser obligatorio antes de enviar la primera notificación.

## Cómo guardarlos

Un PDF por proveedor, con la fecha de aceptación en el nombre:

```
legal/dpas/supabase-dpa-2026-08.pdf
legal/dpas/sentry-dpa-2026-08.pdf
legal/dpas/resend-dpa-2026-08.pdf
legal/dpas/vercel-dpa-2026-08.pdf
```

Marca la casilla de esta tabla al guardarlo, para que el estado no viva solo
en la memoria de alguien.

## Cuándo revisarlos

Cuando cambies de proveedor, cuando alguno actualice sus términos, y **antes
de responder a cualquier solicitud de datos de un usuario europeo**. Ese día
no quieres estar buscándolos.

---

Referencia: ANA-38 · Privacy Policy §5 (Proveedores) y §13 (Transferencias
internacionales).
