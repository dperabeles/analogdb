import type { RollListItem } from "@/features/rolls/roll-types";
import type { Database } from "@/types/database";

/**
 * Editar un rollo en la web: lo que no tocaste no se escribe.
 *
 * Antes, guardar el formulario reescribía el rollo entero con lo que el
 * formulario sabía representar, y eso no era todo: el enlace al lente se
 * cambiaba por texto, el formato 35mm y Super8 se borraba (el selector no
 * tenía esas etiquetas), el push "0" pasaba a vacío, la calificación vacía a 0,
 * y la película y los labs se volvían a buscar por nombre aunque nadie los
 * hubiera cambiado.
 *
 * Ahora el formulario lleva los valores con los que se mostró, la acción
 * compara campo por campo y solo escribe lo que cambió. Este archivo no toca la
 * red, para poder probarlo entero (tests/roll-edit.test.js).
 */

type RollUpdate = Database["public"]["Tables"]["rolls"]["Update"];
type FilmType = Database["public"]["Tables"]["film_stocks"]["Insert"]["type"];

/** Los campos del formulario, con el `name` que tienen en el `<form>`. */
export const ROLL_FORM_FIELDS = [
  "code",
  "filmStock",
  "manufacturer",
  "filmType",
  "format",
  "expFresh",
  "iso",
  "exp",
  "isoPushed",
  "pushPull",
  "maker",
  "modelName",
  "cameraFormat",
  "cameraType",
  "cameraMount",
  "lens",
  "locations",
  "photoType",
  "tags",
  "started",
  "finished",
  "expTaken",
  "dev",
  "scan",
  "status",
  "rating",
  "notes"
] as const;

export type RollFormField = (typeof ROLL_FORM_FIELDS)[number];
export type RollFormValues = Record<RollFormField, string>;

export const FILM_TYPES = ["COLOR", "B/W", "SLIDE"];
export const FORMAT_OPTIONS = ["35", "120", "Super8", "110", "16mm", "Large Format"];
export const FRESH_OPTIONS = ["FRESH", "EXPIRED"];

const FORMAT_OPTION_BY_STORED: Record<number, string> = {
  35: "35",
  120: "120",
  8: "Super8",
  110: "110",
  16: "16mm",
  45: "Large Format"
};

export function nullable(value: string | null | undefined) {
  const clean = (value ?? "").trim();
  return clean || null;
}

export function toInt(value: string | null) {
  if (!value || value === "-") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function toDate(value: string | null) {
  if (!value) return null;
  const clean = value.slice(0, 10);
  return clean.length === 10 ? clean : null;
}

export function toArray(value: string | null) {
  if (!value) return [];
  return value
    .split(value.includes("|") ? "|" : ",")
    .map((item) => item.trim())
    .filter(Boolean);
}

export function toFresh(value: string | null) {
  if (value === "FRESH") return true;
  if (value === "EXPIRED") return false;
  return null;
}

export function toFilmType(value: string | null): FilmType {
  if (value === "COLOR" || value === "B/W" || value === "SLIDE") return value;
  return null;
}

export function formatStorageValue(value: string | null) {
  if (!value) return null;
  const clean = value.trim();
  if (/^(35|35mm|135)$/i.test(clean)) return 35;
  if (/^120$/i.test(clean)) return 120;
  if (/^super\s*8$/i.test(clean)) return 8;
  if (/^110$/i.test(clean)) return 110;
  if (/^16mm$/i.test(clean)) return 16;
  if (/^large format$/i.test(clean)) return 45;
  return null;
}

/**
 * La opción del selector para el formato que trae `rolls_flat` ya normalizado
 * ("35mm", "8"). Un formato que el selector no conoce se devuelve tal cual,
 * para ofrecerlo como opción extra en vez de mostrar "—" y borrarlo al guardar.
 */
export function formatOptionValue(value: string | null) {
  const clean = (value ?? "").trim();
  if (!clean) return "";
  const stored = formatStorageValue(clean) ?? (/^\d+$/.test(clean) ? Number(clean) : null);
  return (stored != null && FORMAT_OPTION_BY_STORED[stored]) || clean;
}

/** Las opciones de un selector, más el valor actual si no está entre ellas. */
export function selectOptions(options: readonly string[], current: string) {
  return current && !options.includes(current) ? [...options, current] : [...options];
}

/** Lo que el formulario muestra para un rollo (o vacío, para uno nuevo). */
export function rollFormDefaults(roll?: RollListItem | null): RollFormValues {
  const value = (raw: string | number | null | undefined) => (raw == null ? "" : String(raw));
  return {
    code: value(roll?.code),
    filmStock: value(roll?.filmStock),
    manufacturer: value(roll?.manufacturer),
    filmType: value(roll?.filmType),
    format: formatOptionValue(roll?.format ?? null),
    expFresh: value(roll?.expFresh),
    iso: value(roll?.iso),
    exp: value(roll?.exp),
    isoPushed: value(roll?.isoPushed),
    pushPull: !roll || roll.pushPull === "0" ? "" : roll.pushPull,
    maker: value(roll?.maker),
    modelName: value(roll?.modelName),
    cameraFormat: value(roll?.cameraFormat),
    cameraType: value(roll?.cameraType),
    cameraMount: value(roll?.cameraMount),
    lens: value(roll?.lens),
    locations: value(roll?.locations),
    photoType: value(roll?.photoType),
    tags: value(roll?.tags),
    started: value(roll?.started),
    finished: value(roll?.finished),
    expTaken: value(roll?.expTaken),
    dev: value(roll?.dev),
    scan: value(roll?.scan),
    status: value(roll?.status),
    rating: value(roll?.rating),
    notes: value(roll?.notes)
  };
}

export function readRollForm(form: { get(name: string): unknown }): RollFormValues {
  const values = {} as RollFormValues;
  for (const field of ROLL_FORM_FIELDS) {
    const raw = form.get(field);
    values[field] = raw == null ? "" : String(raw);
  }
  return values;
}

/**
 * Los valores con los que se mostró el formulario. Si faltan o vienen mal
 * formados devuelve null, y la acción los saca del rollo guardado: adivinar
 * aquí sería volver a escribir lo que nadie tocó.
 */
export function parseOriginalValues(raw: unknown): RollFormValues | null {
  if (typeof raw !== "string" || !raw) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const record = parsed as Record<string, unknown>;
  const values = {} as RollFormValues;
  for (const field of ROLL_FORM_FIELDS) {
    const value = record[field];
    if (typeof value !== "string") return null;
    values[field] = value;
  }
  return values;
}

// Un textarea manda los saltos de línea como CRLF; los espacios de los lados
// los quita la acción. Ninguna de las dos cosas es un cambio.
function comparable(value: string) {
  return value.replace(/\r\n?/g, "\n").trim();
}

export function changedRollFields(before: RollFormValues, after: RollFormValues): RollFormField[] {
  return ROLL_FORM_FIELDS.filter((field) => comparable(before[field]) !== comparable(after[field]));
}

export type CameraDetails = { format?: string | null; type?: string | null; mount?: string | null };

export type RollUpdatePlan = {
  /** Columnas que se escriben tal cual. */
  row: RollUpdate;
  /** Referencias que hay que volver a buscar porque cambió su texto. */
  film: boolean;
  camera: boolean;
  dev: boolean;
  scan: boolean;
  /** Solo los datos de cámara que se editaron. */
  cameraDetails: CameraDetails;
};

export function planRollUpdate(changed: readonly RollFormField[], after: RollFormValues): RollUpdatePlan {
  const has = (field: RollFormField) => changed.includes(field);
  const text = (field: RollFormField) => nullable(after[field]);
  const row: RollUpdate = {};

  if (has("code")) {
    const code = text("code");
    if (!code) throw new Error("code is required");
    row.code = code;
  }
  if (has("format")) row.format = formatStorageValue(text("format"));
  if (has("expFresh")) row.fresh = toFresh(text("expFresh"));
  if (has("exp")) row.exp_count = toInt(text("exp"));
  if (has("expTaken")) row.exp_taken = toInt(text("expTaken"));
  if (has("isoPushed")) row.iso_pushed = toInt(text("isoPushed"));
  if (has("pushPull")) row.push_pull = text("pushPull");
  // La web solo conoce el lente como texto: cambiarlo es lo único que
  // sustituye el enlace al catálogo.
  if (has("lens")) {
    row.lens_id = null;
    row.lens = text("lens");
  }
  if (has("locations")) row.locations = toArray(text("locations"));
  if (has("photoType")) row.photo_types = toArray(text("photoType"));
  if (has("tags")) row.tags = toArray(text("tags"));
  if (has("started")) row.started = toDate(text("started"));
  if (has("finished")) row.finished = toDate(text("finished"));
  if (has("status")) row.status = text("status");
  if (has("rating")) row.rating = toInt(text("rating")) || 0;
  if (has("notes")) row.notes = nullable(comparable(after.notes));

  const cameraDetails: CameraDetails = {};
  if (has("cameraFormat")) cameraDetails.format = text("cameraFormat");
  if (has("cameraType")) cameraDetails.type = text("cameraType");
  if (has("cameraMount")) cameraDetails.mount = text("cameraMount");

  return {
    row,
    film: has("filmStock") || has("manufacturer") || has("iso") || has("filmType"),
    camera: has("maker") || has("modelName") || Object.keys(cameraDetails).length > 0,
    dev: has("dev"),
    scan: has("scan"),
    cameraDetails
  };
}
