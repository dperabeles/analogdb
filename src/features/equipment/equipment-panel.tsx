import {
  removeCameraAction,
  removeLensAction,
  saveCameraAction,
  saveLensAction
} from "@/features/equipment/actions";
import type { CameraItem, EquipmentOverview, LensItem } from "@/features/equipment/queries";

type EquipmentPanelProps = {
  overview: EquipmentOverview;
};

function Field({
  label,
  name,
  defaultValue,
  required = false
}: {
  label: string;
  name: string;
  defaultValue?: string | null;
  required?: boolean;
}) {
  return (
    <label>
      {label}
      <input name={name} defaultValue={defaultValue || ""} required={required} />
    </label>
  );
}

function CheckboxField({
  label,
  name,
  defaultChecked
}: {
  label: string;
  name: string;
  defaultChecked: boolean;
}) {
  return (
    <label className="checkbox-field">
      <input type="checkbox" name={name} defaultChecked={defaultChecked} />
      <span>{label}</span>
    </label>
  );
}

function CameraForm({ camera }: { camera?: CameraItem }) {
  return (
    <form className="equipment-form" action={saveCameraAction}>
      {camera ? <input type="hidden" name="cameraId" value={camera.id} /> : null}
      <Field label="Maker" name="maker" defaultValue={camera?.maker} required />
      <Field label="Model" name="model" defaultValue={camera?.model} required />
      <label>
        Format
        <select name="format" defaultValue={camera?.format || ""} required>
          <option value="">Select</option>
          <option value="35mm">35mm</option>
          <option value="120">120</option>
          <option value="6x4.5">6x4.5</option>
          <option value="6x6">6x6</option>
          <option value="6x7">6x7</option>
          <option value="Super 8">Super 8</option>
          <option value="110">110</option>
          <option value="Large Format">Large Format</option>
        </select>
      </label>
      <Field label="Type" name="type" defaultValue={camera?.type} />
      <Field label="Mount" name="mount" defaultValue={camera?.mount} />
      <CheckboxField
        label="Interchangeable lenses"
        name="supportsInterchangeableLenses"
        defaultChecked={camera?.supports_interchangeable_lenses !== false}
      />
      <CheckboxField
        label="Show in quick mode"
        name="showInQuickMode"
        defaultChecked={camera?.show_in_quick_mode !== false}
      />
      <button className="primary-action" type="submit">
        {camera ? "Guardar camara" : "Agregar camara"}
      </button>
    </form>
  );
}

function LensForm({ lens }: { lens?: LensItem }) {
  return (
    <form className="equipment-form" action={saveLensAction}>
      {lens ? <input type="hidden" name="lensId" value={lens.id} /> : null}
      <Field label="Maker" name="maker" defaultValue={lens?.maker} required />
      <Field label="Model" name="model" defaultValue={lens?.model} required />
      <Field label="Mount" name="mount" defaultValue={lens?.mount} required />
      <CheckboxField
        label="Show in quick mode"
        name="showInQuickMode"
        defaultChecked={lens?.show_in_quick_mode !== false}
      />
      <button className="primary-action" type="submit">
        {lens ? "Guardar lente" : "Agregar lente"}
      </button>
    </form>
  );
}

function CameraCard({ camera }: { camera: CameraItem }) {
  return (
    <article className="equipment-card">
      <div className="equipment-card-head">
        <div>
          <span className="roll-code">{camera.maker || "-"}</span>
          <h3>{camera.model || "-"}</h3>
        </div>
        <span className="roll-status">{camera.rollCount} rolls</span>
      </div>
      <div className="equipment-meta">
        <span>{camera.format || "Format pending"}</span>
        <span>{camera.type || "Type pending"}</span>
        <span>{camera.mount || "Mount pending"}</span>
        <span>{camera.supports_interchangeable_lenses ? "Interchangeable" : "Integrated lens"}</span>
        <span>{camera.show_in_quick_mode ? "Quick mode" : "Hidden quick mode"}</span>
      </div>
      <CameraForm camera={camera} />
      <form action={removeCameraAction}>
        <input type="hidden" name="cameraId" value={camera.id} />
        <button className="danger-action" type="submit">
          {camera.rollCount > 0 ? "Ocultar de quick mode" : "Eliminar camara"}
        </button>
      </form>
    </article>
  );
}

function LensCard({ lens }: { lens: LensItem }) {
  return (
    <article className="equipment-card">
      <div className="equipment-card-head">
        <div>
          <span className="roll-code">{lens.maker || "-"}</span>
          <h3>{lens.model || "-"}</h3>
        </div>
        <span className="roll-status">{lens.rollCount} rolls</span>
      </div>
      <div className="equipment-meta">
        <span>{lens.mount || "Mount pending"}</span>
        <span>{lens.show_in_quick_mode ? "Quick mode" : "Hidden quick mode"}</span>
      </div>
      <LensForm lens={lens} />
      <form action={removeLensAction}>
        <input type="hidden" name="lensId" value={lens.id} />
        <button className="danger-action" type="submit">
          {lens.rollCount > 0 ? "Ocultar de quick mode" : "Eliminar lente"}
        </button>
      </form>
    </article>
  );
}

export function EquipmentPanel({ overview }: EquipmentPanelProps) {
  return (
    <div className="equipment-panel">
      {overview.error ? <p className="auth-message auth-message-error">No se pudo cargar equipo: {overview.error}</p> : null}

      <section className="equipment-section">
        <div className="rolls-header">
          <div>
            <div className="eyebrow">Camaras</div>
            <h2>Camaras</h2>
          </div>
          <span className="roll-status">{overview.cameras.length} total</span>
        </div>
        <CameraForm />
        <div className="equipment-grid">
          {overview.cameras.length ? (
            overview.cameras.map((camera) => <CameraCard key={camera.id} camera={camera} />)
          ) : (
            <div className="empty-state">No hay camaras en tu catalogo.</div>
          )}
        </div>
      </section>

      <section className="equipment-section">
        <div className="rolls-header">
          <div>
            <div className="eyebrow">Lentes</div>
            <h2>Lentes</h2>
          </div>
          <span className="roll-status">{overview.lenses.length} total</span>
        </div>
        <LensForm />
        <div className="equipment-grid">
          {overview.lenses.length ? (
            overview.lenses.map((lens) => <LensCard key={lens.id} lens={lens} />)
          ) : (
            <div className="empty-state">No hay lentes en tu catalogo.</div>
          )}
        </div>
      </section>
    </div>
  );
}
