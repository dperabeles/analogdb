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

      {filteredRolls.length ? (
        <div className="table-card">
          <div className="table-scroll">
            <table className="database-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Rollo</th>
                  <th>Tipo</th>
                  <th>Formato</th>
                  <th>Estado</th>
                  <th>ISO</th>
                  <th>Cámara</th>
                  <th>Lente</th>
                  <th>Ubicación</th>
                  <th>Category</th>
                  <th>Fecha</th>
                  <th># Exp</th>
                  <th>Push/Pull</th>
                  <th>Lab</th>
                  <th>Rating</th>
                </tr>
              </thead>
              <tbody>
                {filteredRolls.map((roll) => (
                  <tr key={roll.id}>
                    <td>
                      <Link className="roll-id" href={`/rolls/${encodeURIComponent(roll.code)}`}>
                        {roll.code}
                      </Link>
                    </td>
                    <td>
                      <span className="database-roll-main">{roll.filmStock || "Sin stock"}</span>
                      <span className="database-roll-sub">{roll.manufacturer || "Manufacturer pending"}</span>
                    </td>
                    <td>{roll.filmType || "—"}</td>
                    <td>{roll.format || "—"}</td>
                    <td>{STATUS_LABELS[roll.status] || roll.status}</td>
                    <td>{roll.iso ?? roll.isoPushed ?? "—"}</td>
                    <td>{[roll.maker, roll.modelName].filter(Boolean).join(" ") || "—"}</td>
                    <td>{roll.lens || "—"}</td>
                    <td>{roll.locations || "—"}</td>
                    <td>{roll.photoType || "—"}</td>
                    <td>{roll.started || roll.finished || "—"}</td>
                    <td>{roll.expTaken || roll.exp || "—"}</td>
                    <td>{roll.pushPull || "0"}</td>
                    <td>{roll.dev || roll.scan || "—"}</td>
                    <td>{stars(roll.rating)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
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
