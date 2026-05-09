import { STATUS_LABELS, type RollFilters } from "@/features/rolls/roll-types";

type RollFiltersProps = {
  filters: RollFilters;
};

const SORT_LABELS = [
  ["newest", "Recientes"],
  ["started", "Inicio"],
  ["finished", "Finalizados"],
  ["rating", "Rating"]
];

export function RollFilters({ filters }: RollFiltersProps) {
  return (
    <form className="roll-filters" action="/dashboard">
      <label>
        Status
        <select name="status" defaultValue={filters.status || ""}>
          <option value="">Todos</option>
          {Object.entries(STATUS_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>

      <label>
        Buscar
        <input name="q" type="search" defaultValue={filters.q || ""} placeholder="Stock, cámara, lugar..." />
      </label>

      <label>
        Orden
        <select name="sort" defaultValue={filters.sort || "newest"}>
          {SORT_LABELS.map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>

      <button className="secondary-action" type="submit">
        Filtrar
      </button>
    </form>
  );
}
