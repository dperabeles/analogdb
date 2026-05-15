import Link from "next/link";
import type { ReactNode } from "react";
import { deleteRollAction } from "@/features/rolls/actions";
import { STATUS_LABELS, type RollListItem } from "@/features/rolls/roll-types";

type RollDetailProps = {
  roll: RollListItem;
};

function valueLabel(value: string | number | null | undefined) {
  return value || "—";
}

function dateLabel(value: string | null | undefined) {
  if (!value) return "—";
  const date = new Date(`${value}T12:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString("es-MX", { day: "numeric", month: "short", year: "numeric" });
}

function badgeClass(value: string | null | undefined) {
  if (value === "COLOR") return "badge badge-color";
  if (value === "B/W") return "badge badge-bw";
  if (value === "SLIDE") return "badge badge-slide";
  return "badge";
}

function Field({ label, value, accent = false }: { label: string; value: string | number | null | undefined; accent?: boolean }) {
  return (
    <div className="ed-modal-row">
      <span className="ed-modal-key">{label}</span>
      <span className={`ed-modal-val${accent ? " accent" : ""}`}>{valueLabel(value)}</span>
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="ed-modal-section">
      <div className="ed-modal-sec-title">{title}</div>
      {children}
    </section>
  );
}

function Chronology({ roll }: { roll: RollListItem }) {
  const steps = [
    { label: "CARGADO", active: true, date: roll.started },
    { label: "DISPARADO", active: Boolean(roll.finished), date: roll.finished },
    { label: "EN LAB", active: roll.status === "In Development" || roll.status === "Developed" || roll.status === "Archived", date: null },
    { label: "REVELADO", active: roll.status === "Developed" || roll.status === "Archived", date: null },
    { label: "ARCHIVADO", active: roll.status === "Archived", date: null }
  ];

  return (
    <div className="ed-cronologia">
      <div className="ed-cron-kicker">CRONOLOGÍA</div>
      <div className="ed-cron-track">
        {steps.map((step) => (
          <div className="ed-cron-step" key={step.label}>
            <div className={`ed-cron-dot${step.active ? " filled" : ""}`} />
            <div className="ed-cron-step-label">{step.label}</div>
            <div className="ed-cron-step-date">{dateLabel(step.date)}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function RollDetail({ roll }: RollDetailProps) {
  return (
    <article className="roll-detail">
      <header className="modal-head roll-detail-modal-head">
        <div className="modal-roll-id">{roll.code}</div>
        <div className="modal-head-text">
          <div className="modal-tag">NÚM. DE ROLLO</div>
          <div className="modal-roll-name">
            {roll.filmStock || "—"}
            <span className="sep"> · </span>
            {roll.modelName || "—"}
          </div>
        </div>
        <span className="roll-status">{STATUS_LABELS[roll.status] || roll.status}</span>
      </header>

      <div className="ed-modal-grid">
        <Section title="Film Info">
          <div className="ed-modal-row">
            <span className="ed-modal-key">Tipo</span>
            <span className="ed-modal-val">{roll.filmType ? <span className={badgeClass(roll.filmType)}>{roll.filmType}</span> : "—"}</span>
          </div>
          <div className="ed-modal-row">
            <span className="ed-modal-key">Formato</span>
            <span className="ed-modal-val">{roll.format ? <span className="badge">{roll.format}</span> : "—"}</span>
          </div>
          <Field label="Film Stock" value={roll.filmStock} accent />
          <Field label="Fabricante" value={roll.manufacturer} />
          <Field label="ISO" value={roll.iso} />
          <Field label="Exposiciones" value={roll.exp} />
          <Field label="Estado" value={roll.expFresh} />
        </Section>

        <Section title="Ubicación">
          <Field label="Lugares" value={roll.locations} />
          <Field label="Categories" value={roll.photoType} />
          <Field label="Tags" value={roll.tags} accent />
          <Field label="ISO @" value={roll.isoPushed} />
          <Field label="Inicio" value={dateLabel(roll.started)} />
          <Field label="Fin" value={dateLabel(roll.finished)} />
          <Field label="Exp finales" value={roll.expTaken} />
          <Field label="Push/Pull" value={roll.pushPull} />
        </Section>

        <Section title="Cámara &amp; Lente">
          <Field label="Marca" value={roll.maker} />
          <Field label="Modelo" value={roll.modelName} />
          <Field label="Formato cám." value={roll.cameraFormat} />
          <Field label="Tipo cám." value={roll.cameraType} />
          <Field label="Montura cám." value={roll.cameraMount} />
          <Field label="Lente" value={roll.lens} />
        </Section>

        <Section title="Lab &amp; Review">
          <Field label="Revelado" value={roll.dev} />
          <Field label="Scan" value={roll.scan} />
          <Field label="Status" value={STATUS_LABELS[roll.status] || roll.status} />
          <Field label="Rating" value={roll.rating} />
          <Field label="Settings por frame" value={roll.frameSettings} />
        </Section>
      </div>

      <Chronology roll={roll} />

      {roll.notes ? <div className="ed-modal-notes">&quot;{roll.notes}&quot;</div> : null}

      <div className="ed-modal-actions">
        <Link className="ed-modal-edit-btn" href={`/rolls/${encodeURIComponent(roll.code)}/edit`}>
          Editar rollo
        </Link>
        <form action={deleteRollAction}>
          <input name="code" type="hidden" value={roll.code} />
          <button className="btn-danger" type="submit">
            Eliminar
          </button>
        </form>
      </div>
    </article>
  );
}
