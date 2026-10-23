import { saveRollAction } from "@/features/rolls/actions";
import { FILM_TYPES, FORMAT_OPTIONS, FRESH_OPTIONS, rollFormDefaults, selectOptions } from "@/features/rolls/roll-edit";
import { STATUS_LABELS, type RollListItem } from "@/features/rolls/roll-types";

type RollFormProps = {
  roll?: RollListItem | null;
};

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
          {selectOptions(options, defaultValue || "").map((option) => (
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
  // Lo que se muestra es también contra lo que la acción compara al guardar:
  // solo se escribe lo que cambió (ver roll-edit.ts).
  const values = rollFormDefaults(roll);
  return (
    <form className="roll-form" action={saveRollAction}>
      <input name="originalCode" type="hidden" value={roll?.code || ""} />
      {roll ? <input name="originalValues" type="hidden" value={JSON.stringify(values)} /> : null}

      <div className="editor-grid">
        <section className="editor-section">
          <div className="editor-sec-title">Film Info</div>
          <Field label="Código" name="code" defaultValue={values.code} required />
          <Field label="Film stock" name="filmStock" defaultValue={values.filmStock} />
          <Field label="Fabricante" name="manufacturer" defaultValue={values.manufacturer} />
          <SelectField label="Tipo" name="filmType" defaultValue={values.filmType} options={FILM_TYPES} />
          <SelectField label="Formato" name="format" defaultValue={values.format} options={FORMAT_OPTIONS} />
          <SelectField label="Fresh/Expired" name="expFresh" defaultValue={values.expFresh} options={FRESH_OPTIONS} />
          <Field label="ISO" name="iso" type="number" defaultValue={values.iso} />
          <Field label="Exposiciones" name="exp" type="number" defaultValue={values.exp} />
          <Field label="ISO @" name="isoPushed" type="number" defaultValue={values.isoPushed} />
          <Field label="Push/Pull" name="pushPull" defaultValue={values.pushPull} />
        </section>

        <section className="editor-section">
          <div className="editor-sec-title">Cámara &amp; Lente</div>
          <Field label="Marca cámara" name="maker" defaultValue={values.maker} />
          <Field label="Modelo cámara" name="modelName" defaultValue={values.modelName} />
          <Field label="Formato cámara" name="cameraFormat" defaultValue={values.cameraFormat} />
          <Field label="Tipo cámara" name="cameraType" defaultValue={values.cameraType} />
          <Field label="Montura cámara" name="cameraMount" defaultValue={values.cameraMount} />
          <Field label="Lente" name="lens" defaultValue={values.lens} />
        </section>

        <section className="editor-section">
          <div className="editor-sec-title">Ubicación</div>
          <Field label="Ubicaciones" name="locations" defaultValue={values.locations} />
          <Field label="Categorías" name="photoType" defaultValue={values.photoType} />
          <Field label="Tags" name="tags" defaultValue={values.tags} />
          <Field label="Inicio" name="started" type="date" defaultValue={values.started} />
          <Field label="Fin" name="finished" type="date" defaultValue={values.finished} />
          <Field label="Exp finales" name="expTaken" type="number" defaultValue={values.expTaken} />
          <Field label="Lab revelado" name="dev" defaultValue={values.dev} />
          <Field label="Lab scan" name="scan" defaultValue={values.scan} />
          <SelectField label="Status" name="status" defaultValue={values.status} options={Object.keys(STATUS_LABELS)} />
          <Field label="Rating" name="rating" type="number" defaultValue={values.rating} />
        </section>

        <section className="editor-section">
          <div className="editor-sec-title">Notas</div>
          <label className="editor-notes-row">
            <span className="editor-key">Notas</span>
            <textarea name="notes" defaultValue={values.notes} />
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
