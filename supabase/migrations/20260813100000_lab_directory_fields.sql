-- Campos del directorio de laboratorios.
--
-- El directorio responde una pregunta: "¿dónde revelo ESTO?". Hoy solo sabe
-- el nombre, la ciudad y el Instagram, que no alcanzan para responderla.
--
-- ── Qué se añade y por qué ────────────────────────────────────────────────
--
--   services       Lo que de verdad decide. Si disparas diapositiva, la mitad
--                  de los labs no te sirven — y hoy no hay forma de saberlo
--                  sin preguntar.
--   formats        Mismo caso: con un 120 en la mano, muchos quedan fuera.
--   accepts_mail   Desbloquea el catálogo entero. Alguien en Oaxaca puede usar
--                  un lab de CDMX si sabe que recibe envíos. Multiplica las
--                  opciones reales sin agregar un solo lab.
--   address        Para llegar. Se combina con `place_id` (ya existía, vacía)
--                  para abrir Maps justo en el negocio.
--   website        Canal de contacto.
--
-- ── Qué NO se añade, a propósito ──────────────────────────────────────────
--
--   Horarios y precios — se quedan viejos en semanas y nadie los mantiene.
--   Peor que no tenerlos: mandas a alguien a una puerta cerrada con tu
--   información.
--
--   Teléfono / WhatsApp — decisión de Diego, y es la correcta: el WhatsApp de
--   un laboratorio pequeño suele ser el número PERSONAL de su dueño. Eso es
--   dato personal de una persona identificable, con las obligaciones que eso
--   arrastra. Instagram y sitio web son canales que el negocio publica él
--   mismo; un número de móvil, no.
--
-- ── Vocabulario cerrado ───────────────────────────────────────────────────
--
-- `services` y `formats` llevan restricción de contenido. La lección de las
-- marcas de cámara (ANA-98) fue que el texto libre se fragmenta solo: sin
-- esto acabaríamos con 'c41', 'C-41', 'C41' y 'color' contando como cuatro
-- servicios distintos.

begin;

alter table public.labs
  add column if not exists address text,
  add column if not exists website text,
  add column if not exists accepts_mail boolean not null default false,
  add column if not exists services text[] not null default '{}',
  add column if not exists formats text[] not null default '{}';

comment on column public.labs.address is
  'Dirección de calle. Se usa con place_id para abrir Maps.';
comment on column public.labs.website is
  'URL del sitio. Sin teléfono a propósito: el móvil de un lab pequeño suele ser personal.';
comment on column public.labs.accepts_mail is
  'Recibe rollos por correo. Permite usar un lab de otra ciudad.';
comment on column public.labs.services is
  'Vocabulario cerrado: c41 · e6 · bw · scan · print.';
comment on column public.labs.formats is
  'Vocabulario cerrado: 35mm · 120 · large · super8 · 110.';

-- Las restricciones se añaden por separado y con NOT VALID primero sería
-- innecesario: la tabla tiene 34 filas y todas arrancan con array vacío, que
-- satisface el check trivialmente.
alter table public.labs
  drop constraint if exists labs_services_vocab;
alter table public.labs
  add constraint labs_services_vocab
  check (services <@ array['c41', 'e6', 'bw', 'scan', 'print']::text[]);

alter table public.labs
  drop constraint if exists labs_formats_vocab;
alter table public.labs
  add constraint labs_formats_vocab
  check (formats <@ array['35mm', '120', 'large', 'super8', '110']::text[]);

commit;
