-- labs.instagram solo puede ser un handle, nunca una URL
--
-- El catálogo de labs es COMPARTIDO y cualquier usuario autenticado puede dar
-- de alta uno (política shared_labs_insert). Lo que escriba se le enseña a
-- todos los demás.
--
-- La app abría ese valor como enlace externo y, si empezaba por http, lo
-- abría TAL CUAL: bastaba con dar de alta un lab con nombre creíble para
-- mandar a otros usuarios al sitio de uno. Ya está arreglado en la app
-- (analogdb-mobile#57), que ahora reconstruye la URL contra instagram.com en
-- vez de confiar en lo guardado.
--
-- Esto es la segunda capa, y es la que de verdad cierra la puerta: que el
-- valor peligroso NO SE PUEDA ESCRIBIR. Arreglar solo el cliente deja el dato
-- envenenado esperando a la próxima pantalla que lo pinte — el `website`, un
-- correo, la webapp.
--
-- Sale gratis: los 34 labs de hoy ya son handles limpios, verificado antes.
alter table public.labs drop constraint if exists labs_instagram_handle;

alter table public.labs
  add constraint labs_instagram_handle
  check (
    instagram is null
    or btrim(instagram) = ''
    -- Lo que Instagram permite: letras, dígitos, punto y guion bajo, hasta 30.
    -- Se tolera la arroba inicial porque la gente la escribe.
    or instagram ~ '^@?[A-Za-z0-9._]{1,30}$'
  );
