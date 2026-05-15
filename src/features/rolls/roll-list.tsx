import Link from "next/link";
import {
  filterRolls,
  normalizeRollFilters,
  sortRolls,
  STATUS_LABELS,
  type RollFilters,
  type RollSort,
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

const TABLE_COLUMNS: { label: string; sort: RollSort }[] = [
  { label: "#", sort: "code" },
  { label: "Rollo", sort: "filmStock" },
  { label: "Tipo", sort: "filmType" },
  { label: "Formato", sort: "format" },
  { label: "Estado", sort: "expFresh" },
  { label: "ISO", sort: "iso" },
  { label: "Cámara", sort: "camera" },
  { label: "Lente", sort: "lens" },
  { label: "Ubicación", sort: "locations" },
  { label: "Category", sort: "photoType" },
  { label: "Fecha", sort: "started" },
  { label: "# Exp", sort: "expTaken" },
  { label: "Push/Pull", sort: "pushPull" },
  { label: "Lab", sort: "lab" },
  { label: "Rating", sort: "rating" }
];

function sortLink(filters: RollFilters, sort: RollSort) {
  const params = new URLSearchParams();
  const nextDir = filters.sort === sort && filters.sortDir === "asc" ? "desc" : "asc";

  (["status", "q", "filmType", "format", "expFresh", "camera", "lab"] as const).forEach((key) => {
    const value = filters[key];
    if (value) params.set(key, value);
  });

  params.set("sort", sort);
  params.set("sortDir", nextDir);

  return `/database?${params.toString()}`;
}

export function RollList({ rolls, filters, error }: RollListProps) {
  const safeFilters = normalizeRollFilters(filters);
  const filteredRolls = sortRolls(filterRolls(rolls, safeFilters), safeFilters.sort, safeFilters.sortDir);

  return (
    <section className="rolls-panel" aria-label="Roll archive">
      <div className="editorial-section-head rolls-header">
        <span className="editorial-section-num">I.</span>
        <div>
          <h2>Roll archive</h2>
          <p>Indice privado sincronizado con la beta actual.</p>
        </div>
      </div>

      <RollFiltersForm filters={safeFilters} rolls={rolls} />

      <div className="filter-count">
        {filteredRolls.length} / {rolls.length} rollos
      </div>

      {error ? <p className="auth-message auth-message-error">No se pudieron cargar los rolls: {error}</p> : null}

      {filteredRolls.length ? (
        <div className="table-card">
          <div className="table-scroll">
            <table className="database-table">
              <thead>
                <tr>
                  {TABLE_COLUMNS.map((column) => {
                    const active = safeFilters.sort === column.sort;
                    const sortClass = active ? (safeFilters.sortDir === "asc" ? "sort-asc" : "sort-desc") : undefined;

                    return (
                      <th
                        key={column.sort}
                        className={sortClass}
                        aria-sort={active ? (safeFilters.sortDir === "asc" ? "ascending" : "descending") : "none"}
                      >
                        <Link href={sortLink(safeFilters, column.sort)}>{column.label}</Link>
                      </th>
                    );
                  })}
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
