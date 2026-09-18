-- Documentar qué significa `show_in_quick_mode` en cameras y lenses.
--
-- ── Por qué ────────────────────────────────────────────────────────────────
--
-- La columna nació como un detalle de interfaz ("mostrarla en el modo rápido")
-- pero siempre significó otra cosa: **si la persona sigue teniendo el equipo**.
-- El propio texto de ayuda de la app ya lo decía ("ej. equipo que ya
-- vendiste"), y en producción la única persona que la ha usado la usó así: 3
-- cámaras apagadas, 2 de ellas con rollos detrás.
--
-- En la app el concepto ya se renombró a activo/inactivo. La columna se queda
-- con el nombre viejo a propósito (ver `Camera.active` en el repo mobile), así
-- que el esquema tiene que decir qué es — si no, el nombre miente y el
-- siguiente que lo lea creerá que apagarla solo afecta a un atajo de la
-- interfaz.
--
-- Solo cambia metadatos: ni datos, ni permisos, ni comportamiento.

comment on column public.cameras.show_in_quick_mode is
  'ACTIVO/INACTIVO (no solo "modo rapido"). true = la persona sigue teniendo '
  'la camara. false = la vendio o ya no la usa: sale del modo rapido y del '
  'alta rapida, pero sigue disponible en el formulario completo (un rollo se '
  'puede capturar un ano despues de dispararse) y sigue en los rollos que ya '
  'la usaron. El nombre de la columna es historico.';

comment on column public.lenses.show_in_quick_mode is
  'ACTIVO/INACTIVO (no solo "modo rapido"). Ver cameras.show_in_quick_mode.';
