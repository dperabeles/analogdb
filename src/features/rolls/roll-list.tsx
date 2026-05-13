import Link from "next/link";
import {
  filterRolls,
  normalizeRollSort,
  sortRolls,
  STATUS_LABELS,
  type RollFilters,
  type RollListItem
} from "@/features/rolls/roll-types";
import { RollFilters as RollFiltersForm } from "@/features/rolls/roll-filters";

type RollListProps = {
  rolls: RollListItem[];
  filters: RollFilters;
  error: string | null;
};

function stars(rating: number | null) {
  if (!rating) return "—";
  const bounded = Math.max(1, Math.min(rating, 5));
  return "★".repeat(bounded) + "☆".repeat(5 - bounded);
}

function countByStatus(rolls: RollListItem[], status: string) {
  return rolls.filter((roll) => roll.status === status).length;
}

export function RollList({ rolls, filters, error }: RollListProps) {
  const safeFilters = { ...filters, sort: normalizeRollSort(filters.sort) };
  const filteredRolls = sortRolls(filterRolls(rolls, safeFilters), safeFilters.sort);

  return (
    <section className="rolls-panel" aria-label="Roll archive">
      <div className="editorial-section-head rolls-header">
        <span className="editorial-section-num">I.</span>
        <div>
          <h2>Roll archive</h2>
          <p>Indice privado sincronizado con la beta actual.</p>
        </div>
      </div>

      <RollFiltersForm filters={safeFilters} />

      {error ? <p className="auth-message auth-message-error">No se pudieron cargar los rolls: {error}</p> : null}

      <div className="status-strip" aria-label="Status counts">
        {Object.entries(STATUS_LABELS).map(([status, label]) => (
          <div key={status} className="status-chip">
            <span>{label}</span>
            <strong>{countByStatus(rolls, status)}</strong>
          </div>
        ))}
      </div>

      {filteredRolls.length ? (
        <div className="roll-card-grid">
          {filteredRolls.map((roll) => (
            <Link key={roll.id} className="roll-card" href={`/rolls/${encodeURIComponent(roll.code)}`}>
              <div className="roll-card-top">
                <span className="roll-code">{roll.code}</span>
                <span className="roll-status">{STATUS_LABELS[roll.status] || roll.status}</span>
              </div>
              <div className="roll-stock">
                <span>{roll.filmStock || "Sin stock"}</span>
                <small>{roll.manufacturer || "Manufacturer pending"}</small>
              </div>
              <div className="roll-meta">
                <span>{roll.format || "Formato —"}</span>
                <span>ISO {roll.iso ?? roll.isoPushed ?? "—"}</span>
                {roll.exp || roll.expTaken ? <span>{roll.expTaken || roll.exp} exp</span> : null}
                {roll.frameSettings ? <span>{roll.frameSettings} settings</span> : null}
              </div>
              <div className="roll-meta muted">
                <span>{[roll.maker, roll.modelName].filter(Boolean).join(" ") || "Cámara —"}</span>
                {roll.lens ? <span>{roll.lens}</span> : null}
              </div>
              <div className="roll-card-bottom">
                <span>{roll.started || roll.finished || "Sin fecha"}</span>
                <span>{stars(roll.rating)}</span>
              </div>
            </Link>
          ))}
        </div>
      ) : (
        <div className="empty-state">
          <div className="status-label">Sin resultados</div>
          <p>No hay rolls que coincidan con los filtros actuales.</p>
        </div>
      )}
    </section>
  );
}
