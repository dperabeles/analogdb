-- Separar PROCESO de SERVICIO en el directorio de laboratorios.
--
-- ── El error que corrige ──────────────────────────────────────────────────
--
-- La migración anterior metió en una sola columna dos cosas que no son la
-- misma clase:
--
--     services = ['c41', 'e6', 'bw', 'scan', 'print']
--                 └── química ──┘   └─ servicio ─┘
--
-- Lo cazó Diego, y tiene razón: son ortogonales. Un lab puede escanear sin
-- revelar. Otro revela C-41 pero no E-6. Mezclados no se puede expresar
-- ninguna de las dos cosas — "¿quién ESCANEA gran formato?" era imposible
-- de preguntar.
--
-- Ahora son tres dimensiones, y cada una responde una pregunta distinta:
--
--     services   qué hacen        develop · scan · print
--     processes  con qué química  c41 · e6 · bw · ecn2
--     formats    de qué tamaño    35mm · 120 · large · 110 · aps ·
--                                 super8 · 8mm · 16mm
--
-- ── Por qué se puede hacer sin migrar datos ───────────────────────────────
--
-- Verificado antes de escribir: las columnas están VACÍAS en los 34 labs.
-- Nadie ha llenado nada todavía, así que redefinir el vocabulario no toca
-- un solo dato. Hacerlo ahora cuesta una migración; hacerlo con el CSV ya
-- capturado habría costado una migración Y reinterpretar cada fila.
--
-- ── Formatos nuevos ───────────────────────────────────────────────────────
--
-- APS, 8mm y 16mm los pidió Diego. Faltaban de verdad: 8mm y 16mm son cine
-- casero, que es justo lo que un lab especializado sí procesa y un lab
-- normal no — o sea, exactamente el tipo de dato que hace útil un directorio.
--
-- ECN-2 entra por lo mismo: es el proceso del negativo de cine (Cinestill y
-- compañía) y muy pocos labs lo hacen. Saber cuáles vale oro.

begin;

alter table public.labs
  add column if not exists processes text[] not null default '{}';

comment on column public.labs.processes is
  'Química que procesan. Vocabulario cerrado: c41 · e6 · bw · ecn2.';
comment on column public.labs.services is
  'Qué hacen, independiente de la química. Vocabulario cerrado: develop · scan · print.';
comment on column public.labs.formats is
  'Tamaños que aceptan. Cerrado: 35mm · 120 · large · 110 · aps · super8 · 8mm · 16mm.';

alter table public.labs
  add constraint labs_processes_vocab
  check (processes <@ array['c41', 'e6', 'bw', 'ecn2']::text[]);

-- `services` deja de llevar química: solo qué hacen.
alter table public.labs drop constraint if exists labs_services_vocab;
alter table public.labs
  add constraint labs_services_vocab
  check (services <@ array['develop', 'scan', 'print']::text[]);

-- `formats` gana los tres que faltaban.
alter table public.labs drop constraint if exists labs_formats_vocab;
alter table public.labs
  add constraint labs_formats_vocab
  check (formats <@ array['35mm', '120', 'large', '110', 'aps',
                          'super8', '8mm', '16mm']::text[]);

commit;
