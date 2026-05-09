import { STATUS_LABELS, type RollListItem } from "@/features/rolls/roll-types";

type RollDetailProps = {
  roll: RollListItem;
};

function Field({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <div className="detail-field">
      <span>{label}</span>
      <strong>{value || "—"}</strong>
    </div>
  );
}

export function RollDetail({ roll }: RollDetailProps) {
  return (
    <article className="roll-detail">
      <header className="roll-detail-head">
        <div>
          <div className="eyebrow">Roll detail</div>
          <h1>{roll.code}</h1>
        </div>
        <span className="roll-status">{STATUS_LABELS[roll.status] || roll.status}</span>
      </header>

      <section className="detail-section">
        <h2>Film</h2>
        <div className="detail-grid">
          <Field label="Stock" value={roll.filmStock} />
          <Field label="Fabricante" value={roll.manufacturer} />
          <Field label="Tipo" value={roll.filmType} />
          <Field label="Formato" value={roll.format} />
          <Field label="ISO" value={roll.iso} />
          <Field label="ISO @" value={roll.isoPushed} />
          <Field label="Exposiciones" value={roll.exp} />
          <Field label="Push/Pull" value={roll.pushPull} />
        </div>
      </section>

      <section className="detail-section">
        <h2>Cámara y lente</h2>
        <div className="detail-grid">
          <Field label="Marca" value={roll.maker} />
          <Field label="Modelo" value={roll.modelName} />
          <Field label="Formato cámara" value={roll.cameraFormat} />
          <Field label="Tipo cámara" value={roll.cameraType} />
          <Field label="Montura cámara" value={roll.cameraMount} />
          <Field label="Lente" value={roll.lens} />
          <Field label="Montura lente" value={roll.lensMount} />
        </div>
      </section>

      <section className="detail-section">
        <h2>Archivo</h2>
        <div className="detail-grid">
          <Field label="Ubicaciones" value={roll.locations} />
          <Field label="Categorías" value={roll.photoType} />
          <Field label="Tags" value={roll.tags} />
          <Field label="Inicio" value={roll.started} />
          <Field label="Fin" value={roll.finished} />
          <Field label="Exp finales" value={roll.expTaken} />
          <Field label="Lab revelado" value={roll.dev} />
          <Field label="Lab scan" value={roll.scan} />
          <Field label="Rating" value={roll.rating} />
          <Field label="Settings por frame" value={roll.frameSettings} />
        </div>
      </section>

      {roll.notes ? (
        <section className="detail-section notes-section">
          <h2>Notas</h2>
          <p>{roll.notes}</p>
        </section>
      ) : null}
    </article>
  );
}
