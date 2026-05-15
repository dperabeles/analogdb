import type { Database } from "@/types/database";

export type RollFlatRow = Database["public"]["Views"]["rolls_flat"]["Row"];

export type RollStatus = "In Camera" | "To Develop" | "In Development" | "Developed" | "Archived";

export type RollSort = "newest" | "started" | "finished" | "rating";

export type RollFilters = {
  status?: string;
  q?: string;
  filmType?: string;
  format?: string;
  expFresh?: string;
  camera?: string;
  lab?: string;
  sort?: RollSort;
};

export type RollListItem = {
  id: number;
  code: string;
  filmStock: string | null;
  filmType: string | null;
  manufacturer: string | null;
  format: string | null;
  expFresh: string | null;
  iso: number | null;
  exp: number | null;
  maker: string | null;
  modelName: string | null;
  cameraFormat: string | null;
  cameraType: string | null;
  cameraMount: string | null;
  lens: string | null;
  lensMount: string | null;
  locations: string | null;
  photoType: string | null;
  tags: string | null;
  isoPushed: number | null;
  started: string | null;
  finished: string | null;
  expTaken: number | null;
  pushPull: string;
  dev: string | null;
  scan: string | null;
  status: string;
  rating: number | null;
  notes: string | null;
  frameSettings: number;
};

export const STATUS_LABELS: Record<string, string> = {
  "In Camera": "En cámara",
  "To Develop": "Por revelar",
  "In Development": "En lab",
  Developed: "Revelado",
  Archived: "Archivado"
};

export function normalizePushPull(value: string | null) {
  if (value == null) return "0";
  const compact = String(value).trim().replace(/[()\s]/g, "");
  if (!compact || compact === "-" || compact === "—" || compact.toLowerCase() === "none") {
    return "0";
  }

  const match = compact.match(/^([+-]?)(\d+)$/);
  if (!match) return "0";

  const parsed = Number.parseInt(match[2] || "0", 10);
  if (!Number.isFinite(parsed) || parsed === 0) return "0";

  const clipped = Math.min(parsed, 5);
  return `${match[1] === "-" ? "-" : "+"}${clipped}`;
}

export function normalizeFormatValue(value: string | number | null) {
  if (!value) return null;
  const clean = String(value).trim();
  if (/^(35|35mm|135)$/i.test(clean)) return "35mm";
  if (/^(120|medium format|mf)$/i.test(clean)) return "120";
  if (/^large format$/i.test(clean)) return "Large Format";
  return clean;
}

export function mapRollFlatRow(row: RollFlatRow): RollListItem | null {
  if (!row["#"]) return null;

  return {
    id: row.id,
    code: row["#"],
    filmStock: row["FILM STOCK"],
    filmType: row["FILM TYPE"],
    manufacturer: row.MANUFACTURER,
    format: normalizeFormatValue(row.FORMAT),
    expFresh: row["EXP/FRESH"],
    iso: row.ISO,
    exp: row.EXP,
    maker: row.MAKER,
    modelName: row["MODEL NAME"],
    cameraFormat: row["C. FORMAT"],
    cameraType: row["C. TYPE"],
    cameraMount: row["C. MOUNT"],
    lens: row.LENS,
    lensMount: row["LENS MOUNT"],
    locations: row.LOCATIONS,
    photoType: row["PHOTO TYPE"],
    tags: row.TAGS,
    isoPushed: row["ISO @"],
    started: row.STARTED,
    finished: row.FINISHED,
    expTaken: row["# EXP"],
    pushPull: normalizePushPull(row["PUSH/PULL"]),
    dev: row.DEV,
    scan: row.SCAN,
    status: row.STATUS || "In Camera",
    rating: row.RATING,
    notes: row.NOTES,
    frameSettings: row["FRAME SETTINGS"] || 0
  };
}

export function filterRolls(rolls: RollListItem[], filters: RollFilters) {
  const status = filters.status?.trim();
  const q = filters.q?.trim().toLowerCase();
  const filmType = filters.filmType?.trim();
  const format = filters.format?.trim();
  const expFresh = filters.expFresh?.trim();
  const camera = filters.camera?.trim();
  const lab = filters.lab?.trim();

  return rolls.filter((roll) => {
    if (status && roll.status !== status) return false;
    if (filmType && roll.filmType !== filmType) return false;
    if (format && normalizeFormatValue(roll.format) !== normalizeFormatValue(format)) return false;
    if (expFresh && roll.expFresh !== expFresh) return false;
    if (camera && roll.modelName !== camera) return false;
    if (lab && roll.dev !== lab) return false;
    if (!q) return true;

    const haystack = [
      roll.code,
      roll.filmStock,
      roll.manufacturer,
      roll.filmType,
      roll.format,
      roll.maker,
      roll.modelName,
      roll.lens,
      roll.locations,
      roll.photoType,
      roll.tags,
      roll.dev,
      roll.notes
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

    return haystack.includes(q);
  });
}

export function sortRolls(rolls: RollListItem[], sort: RollSort = "newest") {
  const copy = [...rolls];
  const dateValue = (value: string | null) => (value ? Date.parse(value) || 0 : 0);

  return copy.sort((a, b) => {
    if (sort === "started") return dateValue(b.started) - dateValue(a.started) || b.id - a.id;
    if (sort === "finished") return dateValue(b.finished) - dateValue(a.finished) || b.id - a.id;
    if (sort === "rating") return (b.rating || 0) - (a.rating || 0) || b.id - a.id;
    return b.id - a.id;
  });
}

export function normalizeRollSort(value: string | undefined): RollSort {
  if (value === "started" || value === "finished" || value === "rating") return value;
  return "newest";
}
