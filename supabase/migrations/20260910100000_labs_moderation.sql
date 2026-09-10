-- Cola de moderación para el catálogo de labs
--
-- El catálogo es COMPARTIDO: cualquier usuario autenticado puede dar de alta
-- un lab (política shared_labs_insert) y hasta hoy aparecía de inmediato en la
-- pantalla de todos los demás. Sin forma de saber siquiera QUIÉN lo agregó.
--
-- Eso ya causó un problema de seguridad real (el enlace de Instagram,
-- #30/mobile#57). Aquel se cerró por el lado del dato; esto cierra el otro
-- lado: que lo que alguien escriba no llegue a los demás sin revisarse.
--
-- ── Lo que NO puede pasar ────────────────────────────────────────────────
--
-- Los 34 labs de hoy tienen que seguir visibles para todos. Se marcan
-- 'approved' explícitamente en esta misma migración, ANTES de que nada lea la
-- columna. El default 'pending' aplica solo a los que vengan después.

begin;

alter table public.labs
  add column if not exists status text not null default 'pending',
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz;

-- Todo lo que ya existía se aprueba. Sin esto, el default 'pending' escondería
-- el catálogo entero a todo el mundo en el instante en que cambie la RLS.
update public.labs set status = 'approved' where status = 'pending';

alter table public.labs drop constraint if exists labs_status_vocab;
alter table public.labs
  add constraint labs_status_vocab
  check (status in ('pending', 'approved', 'rejected'));

create index if not exists labs_status_idx on public.labs (status)
  where status <> 'approved';

-- ── Quién crea qué: se impone en el servidor, no se pide al cliente ──────
--
-- Un trigger y no una WITH CHECK sobre columnas: así ningún cliente puede
-- mentir sobre `created_by` ni auto-aprobarse, ni siquiera llamando a la API
-- directamente, y el código de la app no tiene que acordarse de nada.
--
-- Mismo principio que el arreglo del enlace de Instagram: no validar lo que
-- llega, sino reconstruirlo.
create or replace function public.labs_force_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.created_by := auth.uid();
  new.created_at := now();
  new.reviewed_by := null;
  new.reviewed_at := null;
  -- Un admin que da de alta un lab no se hace cola a sí mismo.
  if public.app_is_admin(auth.uid()) then
    new.status := coalesce(nullif(new.status, ''), 'approved');
  else
    new.status := 'pending';
  end if;
  return new;
end $$;

drop trigger if exists labs_force_submission_trg on public.labs;
create trigger labs_force_submission_trg
  before insert on public.labs
  for each row execute function public.labs_force_submission();

-- ── Visibilidad ─────────────────────────────────────────────────────────
--
-- Ves un lab si está aprobado, si lo propusiste tú, o si eres admin.
--
-- Que el proponente siga viéndolo NO es un detalle: da de alta el lab a mitad
-- de registrar un rollo, y si desapareciera mientras se revisa, su rollo se
-- quedaría sin laboratorio.
drop policy if exists shared_labs_select on public.labs;
create policy shared_labs_select on public.labs
  for select
  using (
    status = 'approved'
    or created_by = auth.uid()
    or public.app_is_admin(auth.uid())
  );

-- ── Revisar: solo admin, y solo por RPC ─────────────────────────────────
create or replace function public.review_lab(p_lab_id bigint, p_decision text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.app_is_admin(auth.uid()) then
    raise exception 'admin only';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected';
  end if;

  update public.labs
     set status = p_decision,
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_lab_id;

  if not found then
    raise exception 'lab not found';
  end if;
end $$;

revoke all on function public.review_lab(bigint, text) from public, anon;
grant execute on function public.review_lab(bigint, text) to authenticated;

commit;
