import { saveRollAction } from "@/features/rolls/actions";
import { STATUS_LABELS, type RollListItem } from "@/features/rolls/roll-types";

type RollFormProps = {
  roll?: RollListItem | null;
};

const FILM_TYPES = ["COLOR", "B/W", "SLIDE"];
const FORMATS = ["35", "120", "Super8", "110", "16mm", "Large Format"];
const FRESH_OPTIONS = ["FRESH", "EXPIRED"];

function Field({
  label,
  name,
  defaultValue,
  type = "text",
  required = false
}: {
  label: string;
  name: string;
  defaultValue?: string | number | null;
  type?: string;
  required?: boolean;
}) {
  return (
    <label className="editor-row">
      <span className="editor-key">{label}</span>
      <span className="editor-val">
        <input name={name} type={type} defaultValue={defaultValue ?? ""} required={required} />
      </span>
    </label>
  );
}

function SelectField({
  label,
  name,
  defaultValue,
  options
}: {
  label: string;
  name: string;
  defaultValue?: string | null;
  options: string[];
}) {
  return (
    <label className="editor-row">
      <span className="editor-key">{label}</span>
      <span className="editor-val">
        <select name={name} defaultValue={defaultValue || ""}>
          <option value="">—</option>
          {options.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
      </span>
    </label>
  );
}

export function RollForm({ roll }: RollFormProps) {
  return (
    <form className="roll-form" action={saveRollAction}>
      <input name="originalCode" type="hidden" value={roll?.code || ""} />

      <div className="editor-grid">
        <section className="editor-section">
          <div className="editor-sec-title">Film Info</div>
          <Field label="Código" name="code" defaultValue={roll?.code} required />
          <Field label="Film stock" name="filmStock" defaultValue={roll?.filmStock} />
          <Field label="Fabricante" name="manufacturer" defaultValue={roll?.manufacturer} />
          <SelectField label="Tipo" name="filmType" defaultValue={roll?.filmType} options={FILM_TYPES} />
          <SelectField label="Formato" name="format" defaultValue={roll?.format} options={FORMATS} />
          <SelectField label="Fresh/Expired" name="expFresh" defaultValue={roll?.expFresh} options={FRESH_OPTIONS} />
          <Field label="ISO" name="iso" type="number" defaultValue={roll?.iso} />
          <Field label="Exposiciones" name="exp" type="number" defaultValue={roll?.exp} />
          <Field label="ISO @" name="isoPushed" type="number" defaultValue={roll?.isoPushed} />
          <Field label="Push/Pull" name="pushPull" defaultValue={roll?.pushPull === "0" ? "" : roll?.pushPull} />
        </section>

        <section className="editor-section">
          <div className="editor-sec-title">Cámara &amp; Lente</div>
          <Field label="Marca cámara" name="maker" defaultValue={roll?.maker} />
          <Field label="Modelo cámara" name="modelName" defaultValue={roll?.modelName} />
          <Field label="Formato cámara" name="cameraFormat" defaultValue={roll?.cameraFormat} />
          <Field label="Tipo cámara" name="cameraType" defaultValue={roll?.cameraType} />
          <Field label="Montura cámara" name="cameraMount" defaultValue={roll?.cameraMount} />
          <Field label="Lente" name="lens" defaultValue={roll?.lens} />
        </section>

        <section className="editor-section">
          <div className="editor-sec-title">Ubicación</div>
          <Field label="Ubicaciones" name="locations" defaultValue={roll?.locations} />
          <Field label="Categorías" name="photoType" defaultValue={roll?.photoType} />
          <Field label="Tags" name="tags" defaultValue={roll?.tags} />
          <Field label="Inicio" name="started" type="date" defaultValue={roll?.started} />
          <Field label="Fin" name="finished" type="date" defaultValue={roll?.finished} />
          <Field label="Exp finales" name="expTaken" type="number" defaultValue={roll?.expTaken} />
          <Field label="Lab revelado" name="dev" defaultValue={roll?.dev} />
          <Field label="Lab scan" name="scan" defaultValue={roll?.scan} />
          <SelectField label="Status" name="status" defaultValue={roll?.status} options={Object.keys(STATUS_LABELS)} />
          <Field label="Rating" name="rating" type="number" defaultValue={roll?.rating} />
        </section>

        <section className="editor-section">
          <div className="editor-sec-title">Notas</div>
          <label className="editor-notes-row">
            <span className="editor-key">Notas</span>
            <textarea name="notes" defaultValue={roll?.notes || ""} />
          </label>
        </section>
      </div>

      <div className="editor-actions">
        <button className="btn-primary" type="submit">
          {roll ? "Guardar cambios" : "Crear rollo"}
        </button>
      </div>
    </form>
  );
}
