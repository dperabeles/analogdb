import type { RollFilters, RollListItem } from "@/features/rolls/roll-types";

type RollFiltersProps = {
  filters: RollFilters;
  rolls: RollListItem[];
};

const FILM_TYPE_OPTIONS = [
  ["COLOR", "Color"],
  ["B/W", "B/W"],
  ["SLIDE", "Slide"]
];

const FORMAT_OPTIONS = [
  ["35mm", "35mm"],
  ["120", "120"],
  ["Super8", "Super8"],
  ["110", "110"],
  ["16mm", "16mm"],
  ["Large Format", "Large Format"]
];

const FRESH_OPTIONS = [
  ["FRESH", "Fresh"],
  ["EXPIRED", "Expired"]
];

function uniqueSorted(values: Array<string | null | undefined>) {
  return [...new Set(values.map((value) => value?.trim()).filter((value): value is string => Boolean(value)))]
    .sort((a, b) => a.localeCompare(b, "es"));
}

export function RollFilters({ filters, rolls }: RollFiltersProps) {
  const cameras = uniqueSorted(rolls.map((roll) => roll.modelName));
  const labs = uniqueSorted(rolls.map((roll) => roll.dev));

  return (
    <form className="roll-filters" action="/database">
      <label>
        Buscar
        <input name="q" type="search" defaultValue={filters.q || ""} placeholder="Buscar rollos..." />
      </label>

      <label>
        Tipo
        <select name="filmType" defaultValue={filters.filmType || ""}>
          <option value="">Todos los tipos</option>
          {FILM_TYPE_OPTIONS.map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>

      <label>
        Formato
        <select name="format" defaultValue={filters.format || ""}>
          <option value="">Todos los formatos</option>
          {FORMAT_OPTIONS.map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>

      <label>
        Estado
        <select name="expFresh" defaultValue={filters.expFresh || ""}>
          <option value="">Exp / Fresh</option>
          {FRESH_OPTIONS.map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>

      <label>
        Cámara
        <select name="camera" defaultValue={filters.camera || ""}>
          <option value="">Todas las cámaras</option>
          {cameras.map((camera) => (
            <option key={camera} value={camera}>
              {camera}
            </option>
          ))}
        </select>
      </label>

      <label>
        Lab
        <select name="lab" defaultValue={filters.lab || ""}>
          <option value="">Todos los labs</option>
          {labs.map((lab) => (
            <option key={lab} value={lab}>
              {lab}
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
