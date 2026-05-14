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
  required = false,
  placeholder
}: {
  label: string;
  name: string;
  defaultValue?: string | null;
  required?: boolean;
  placeholder?: string;
}) {
  return (
    <label className="cam-modal-field">
      <span className="cam-modal-label">{label}</span>
      <input className="cam-modal-input" name={name} defaultValue={defaultValue || ""} placeholder={placeholder} required={required} />
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
    <label className="cam-modal-check">
      <input type="checkbox" name={name} defaultChecked={defaultChecked} />
      <span>{label}</span>
    </label>
  );
}

function formatDate(value: string | null) {
  if (!value) return "Sin uso aún";
  const date = new Date(`${value}T12:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString("es-MX", { day: "2-digit", month: "short", year: "numeric" });
}

function formatSwatch(format: string | null) {
  const value = String(format || "").toLowerCase();
  if (value.includes("120") || value.startsWith("6x")) return "#9b72cf";
  if (value.includes("110")) return "#5aaf7a";
  if (value.includes("super") || value.includes("16mm")) return "#5b9bd5";
  if (value.includes("4x5") || value.includes("large")) return "#c07a30";
  return "#d94a2a";
}

function CameraForm({ camera, mode = "add" }: { camera?: CameraItem; mode?: "add" | "edit" }) {
  return (
    <form className={`equipment-form cam-inline-form cam-inline-form-${mode}`} action={saveCameraAction}>
      {camera ? <input type="hidden" name="cameraId" value={camera.id} /> : null}
      <Field label="Fabricante" name="maker" defaultValue={camera?.maker} placeholder="PENTAX, CANON, MAMIYA..." required />
      <Field label="Modelo" name="model" defaultValue={camera?.model} placeholder="Super Program, M645J..." required />
      <label className="cam-modal-field">
        <span className="cam-modal-label">Formato</span>
        <select className="cam-modal-select" name="format" defaultValue={camera?.format || ""} required>
          <option value="">Seleccionar</option>
          <option value="35mm">35mm</option>
          <option value="120">120</option>
          <option value="6x4.5">6x4.5</option>
          <option value="6x6">6x6</option>
          <option value="6x7">6x7</option>
          <option value="6x9">6x9</option>
          <option value="4x5">4x5</option>
          <option value="Super 8">Super 8</option>
          <option value="16mm">16mm</option>
          <option value="110">110</option>
          <option value="Otro">Otro</option>
        </select>
      </label>
      <label className="cam-modal-field">
        <span className="cam-modal-label">Tipo de cámara</span>
        <select className="cam-modal-select" name="type" defaultValue={camera?.type || ""}>
          <option value="">Seleccionar</option>
          <option value="SLR">SLR</option>
          <option value="P&S">P&S</option>
          <option value="Rangefinder">Rangefinder</option>
          <option value="TLR">TLR</option>
          <option value="View Camera">View Camera</option>
          <option value="Folding">Folding</option>
          <option value="Disposable">Disposable / Toy</option>
          <option value="Otro">Otro</option>
        </select>
      </label>
      <Field label="Montura" name="mount" defaultValue={camera?.mount} placeholder="Pentax K, Canon FD, LTM..." />
      <CheckboxField
        label="Lente intercambiable"
        name="supportsInterchangeableLenses"
        defaultChecked={camera?.supports_interchangeable_lenses !== false}
      />
      <CheckboxField
        label="Mostrar en modo rápido"
        name="showInQuickMode"
        defaultChecked={camera?.show_in_quick_mode !== false}
      />
      <div className="cam-modal-actions">
        <button className="cam-modal-save" type="submit">
          {camera ? "Guardar cámara" : "Agregar cámara"}
        </button>
      </div>
    </form>
  );
}

function LensForm({ lens, mode = "add" }: { lens?: LensItem; mode?: "add" | "edit" }) {
  return (
    <form className={`equipment-form cam-inline-form cam-inline-form-${mode}`} action={saveLensAction}>
      {lens ? <input type="hidden" name="lensId" value={lens.id} /> : null}
      <Field label="Fabricante" name="maker" defaultValue={lens?.maker} placeholder="Pentax, Canon, Mamiya..." required />
      <Field label="Modelo" name="model" defaultValue={lens?.model} placeholder="Pentax-A 50mm f2.0..." required />
      <Field label="Montura" name="mount" defaultValue={lens?.mount} placeholder="Pentax K, Canon FD, LTM..." required />
      <CheckboxField
        label="Mostrar en modo rápido"
        name="showInQuickMode"
        defaultChecked={lens?.show_in_quick_mode !== false}
      />
      <div className="cam-modal-actions">
        <button className="cam-modal-save" type="submit">
          {lens ? "Guardar lente" : "Agregar lente"}
        </button>
      </div>
    </form>
  );
}

function CameraCard({ camera }: { camera: CameraItem }) {
  return (
    <article className="cam-card">
      <div className="cam-card-maker">{camera.maker || ""}</div>
      <div className="cam-card-model">{camera.model || "—"}</div>
      <div className="cam-card-badges">
        <span className="cam-badge fmt">
          <span className="cam-badge-swatch" style={{ background: formatSwatch(camera.format) }} />
          {camera.format || "Formato pendiente"}
        </span>
        {camera.type ? <span className="cam-badge">{camera.type}</span> : null}
        <span className={camera.mount ? "cam-badge" : "cam-badge muted"}>{camera.mount || "Montura pendiente"}</span>
        <span className={camera.supports_interchangeable_lenses ? "cam-badge" : "cam-badge muted"}>
          {camera.supports_interchangeable_lenses ? "Lente intercambiable" : "Lente integrado"}
        </span>
        {camera.show_in_quick_mode ? null : <span className="cam-badge muted">Oculta modo rápido</span>}
      </div>
      <div className="cam-card-footer">
        <div>
          <div className="cam-card-rolls">
            <b>{camera.rollCount}</b> {camera.rollCount === 1 ? "rollo disparado" : "rollos disparados"}
          </div>
          <div className="cam-card-last">Último uso: {formatDate(camera.lastUsed)}</div>
        </div>
        <form className="cam-card-action-form" action={removeCameraAction}>
          <input type="hidden" name="cameraId" value={camera.id} />
          <button className="cam-card-del" type="submit" title={camera.rollCount > 0 ? "Ocultar de modo rápido" : "Eliminar cámara"}>
            {camera.rollCount > 0 ? "Ocultar" : "Eliminar"}
          </button>
        </form>
      </div>
      <details className="cam-card-edit-panel">
        <summary className="cam-card-edit">Editar</summary>
        <CameraForm camera={camera} mode="edit" />
      </details>
    </article>
  );
}

function LensCard({ lens }: { lens: LensItem }) {
  return (
    <article className="cam-card lens-card">
      <div className="cam-card-maker">{lens.maker || ""}</div>
      <div className="cam-card-model">{lens.model || "—"}</div>
      <div className="cam-card-badges">
        <span className="cam-badge fmt">
          <span className="cam-badge-swatch" style={{ background: "#9c9284" }} />
          {lens.mount || "Montura pendiente"}
        </span>
        {lens.show_in_quick_mode ? null : <span className="cam-badge muted">Oculto</span>}
      </div>
      <div className="cam-card-footer">
        <div>
          <div className="cam-card-rolls">
            <b>{lens.rollCount}</b> {lens.rollCount === 1 ? "rollo asociado" : "rollos asociados"}
          </div>
          <div className="cam-card-last">Último uso: {formatDate(lens.lastUsed)}</div>
        </div>
        <form className="cam-card-action-form" action={removeLensAction}>
          <input type="hidden" name="lensId" value={lens.id} />
          <button className="cam-card-del" type="submit" title={lens.rollCount > 0 ? "Ocultar de modo rápido" : "Eliminar lente"}>
            {lens.rollCount > 0 ? "Ocultar" : "Eliminar"}
          </button>
        </form>
      </div>
      <details className="cam-card-edit-panel">
        <summary className="cam-card-edit">Editar</summary>
        <LensForm lens={lens} mode="edit" />
      </details>
    </article>
  );
}

function CameraUsageChart({ cameras }: { cameras: CameraItem[] }) {
  const sorted = cameras
    .filter((camera) => camera.rollCount > 0)
    .sort((a, b) => b.rollCount - a.rollCount || String(a.model || "").localeCompare(String(b.model || "")));
  const max = sorted[0]?.rollCount || 1;
  return (
    <div className="cam-chart-wrap">
      <div className="cam-chart-title">Rollos por cámara</div>
      <div className="cam-bars-container">
        {sorted.length ? (
          sorted.map((camera) => (
            <div className="cam-bar-row" key={camera.id}>
              <div className="cam-bar-label">
                <div className="cam-bar-model">{camera.model || "—"}</div>
                <div className="cam-bar-maker">{camera.maker || ""}</div>
              </div>
              <div className="cam-bar-area">
                <div className="cam-bar-track">
                  <div className="cam-bar-fill" style={{ width: `${(camera.rollCount / max) * 100}%`, background: formatSwatch(camera.format) }} />
                </div>
                <div className="cam-bar-meta">
                  <span className="cam-bar-segment">
                    <span className="cam-seg-dot" style={{ background: formatSwatch(camera.format) }} />
                    {camera.format || "Formato pendiente"}
                  </span>
                </div>
              </div>
              <div className="cam-bar-count">{camera.rollCount}</div>
            </div>
          ))
        ) : (
          <div className="cam-empty-state">Aún no hay rollos asociados a cámaras.</div>
        )}
      </div>
    </div>
  );
}

function CameraTypeChart({ cameras }: { cameras: CameraItem[] }) {
  const counts = new Map<string, number>();
  for (const camera of cameras) {
    const type = camera.type || "Tipo pendiente";
    counts.set(type, (counts.get(type) || 0) + 1);
  }
  const entries = [...counts.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const max = entries[0]?.[1] || 1;
  return (
    <div className="cam-bottom-grid">
      <div className="stat-card">
        <div className="stat-card-title">Tipo de cámara</div>
        {entries.length ? (
          entries.map(([type, count]) => (
            <div className="bar-row" key={type}>
              <span className="bar-lbl">{type}</span>
              <div className="bar-track">
                <div className="bar-fill" style={{ width: `${(count / max) * 100}%`, background: "#9b72cf" }} />
              </div>
              <span className="bar-num">{count}</span>
            </div>
          ))
        ) : (
          <div className="empty-state">Sin cámaras registradas.</div>
        )}
      </div>
    </div>
  );
}

export function EquipmentPanel({ overview }: EquipmentPanelProps) {
  return (
    <div className="equipment-panel">
      {overview.error ? <p className="auth-message auth-message-error">No se pudo cargar equipo: {overview.error}</p> : null}

      <section className="equipment-section" id="camera-form">
        <div className="ed-section-head">
          <div className="ed-section-num">I.</div>
          <div className="ed-section-copy">
            <h2 className="ed-section-title">Cámaras</h2>
            <div className="ed-section-sub">
              {overview.cameras.length} {overview.cameras.length === 1 ? "cámara" : "cámaras"} en el catálogo
            </div>
          </div>
        </div>
        <CameraForm />
        <div className="cam-catalog-grid">
          {overview.cameras.length ? (
            overview.cameras.map((camera) => <CameraCard key={camera.id} camera={camera} />)
          ) : (
            <div className="cam-empty-state">
              Ninguna cámara en el catálogo aún.
              <div className="cem-sub">Agrega una cámara para comenzar</div>
            </div>
          )}
        </div>
        <div className="cam-stats-label">Estadísticas de uso</div>
        <CameraUsageChart cameras={overview.cameras} />
        <CameraTypeChart cameras={overview.cameras} />
      </section>

      <section className="equipment-section">
        <div className="ed-section-head">
          <div className="ed-section-num">II.</div>
          <div className="ed-section-copy">
            <h2 className="ed-section-title">Lentes</h2>
            <div className="ed-section-sub">
              {overview.lenses.length} {overview.lenses.length === 1 ? "lente" : "lentes"} en el catálogo
            </div>
          </div>
        </div>
        <LensForm />
        <div className="cam-catalog-grid lens-catalog-grid">
          {overview.lenses.length ? (
            overview.lenses.map((lens) => <LensCard key={lens.id} lens={lens} />)
          ) : (
            <div className="cam-empty-state">
              Ningún lente en el catálogo aún.
              <div className="cem-sub">Agrega un lente para completar tu equipo</div>
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
