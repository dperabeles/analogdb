"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import {
  changedRollFields,
  formatStorageValue,
  nullable,
  parseOriginalValues,
  planRollUpdate,
  readRollForm,
  rollFormDefaults,
  toArray,
  toDate,
  toFilmType,
  toFresh,
  toInt,
  type CameraDetails,
  type RollFormValues
} from "@/features/rolls/roll-edit";
import { mapRollFlatRow } from "@/features/rolls/roll-types";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database";

type FilmType = Database["public"]["Tables"]["film_stocks"]["Insert"]["type"];
type RollInsert = Database["public"]["Tables"]["rolls"]["Insert"];
type RollUpdate = Database["public"]["Tables"]["rolls"]["Update"];

function text(formData: FormData, key: string) {
  const value = String(formData.get(key) || "").trim();
  return value || null;
}

function requiredText(formData: FormData, key: string) {
  const value = text(formData, key);
  if (!value) throw new Error(`${key} is required`);
  return value;
}

async function requireApprovedProfile() {
  const { state, profile } = await getCurrentAccessProfile();
  if (state !== "approved" || !profile) {
    throw new Error("Approved session required");
  }
  return profile;
}

type ApprovedProfile = Awaited<ReturnType<typeof requireApprovedProfile>>;

/**
 * Busca la película por fabricante y nombre, y solo la crea si no existe.
 *
 * Antes era un upsert, y el catálogo es compartido: a un admin le reescribía
 * la película de todos (ISO, tipo y `in_catalog = false`, que la saca del
 * catálogo), y a cualquier otra cuenta le fallaba el guardado, porque solo un
 * admin puede actualizar `film_stocks`. El ISO y el tipo solo se usan al crear.
 */
async function resolveFilmStock(manufacturerValue: string | null, nameValue: string | null, iso: number | null, type: FilmType) {
  if (!manufacturerValue && !nameValue) return null;

  const manufacturer = manufacturerValue || "";
  const name = nameValue || "";
  const supabase = await createServerSupabaseClient();
  const find = () =>
    supabase.from("film_stocks").select("id").eq("manufacturer", manufacturer).eq("name", name).limit(1);

  const { data: existing, error: findError } = await find();
  if (findError) throw findError;
  if (existing && existing.length > 0) return existing[0].id;

  const { data, error } = await supabase
    .from("film_stocks")
    .insert({ manufacturer, name, iso, type, in_catalog: false })
    .select("id")
    .single();

  if (error) {
    // Carrera: otro request la creó entre el select y el insert.
    if (error.code === "23505") {
      const { data: raced, error: retryError } = await find();
      if (retryError) throw retryError;
      if (raced && raced.length > 0) return raced[0].id;
    }
    throw error;
  }
  return data.id;
}

/**
 * Resuelve la cámara por marca y modelo. Solo escribe en la cámara los datos
 * de [details]: al cambiar el rollo a otra cámara, el formato, tipo y montura
 * que el formulario traía son los de la cámara anterior y no deben pisar los
 * de la nueva.
 */
async function upsertCamera(ownerUserId: string, maker: string | null, model: string | null, details: CameraDetails) {
  if (!maker && !model) return null;

  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("cameras")
    .upsert(
      {
        owner_user_id: ownerUserId,
        maker,
        model,
        ...details
      },
      { onConflict: "owner_user_id,maker,model" }
    )
    .select("id")
    .single();

  if (error) throw error;
  return data.id;
}

/**
 * Espejo del trigger SQL `labs_match_key_trg`: minúsculas, sin acentos,
 * solo [a-z0-9]. Debe mantenerse idéntico al trigger (y al helper Dart
 * `Lab.normalizeMatchKey` de la app móvil).
 */
function normalizeLabMatchKey(name: string): string {
  const from = "áàäâãéèëêíìïîóòöôõúùüûñç";
  const to = "aaaaaeeeeiiiiooooouuuunc";
  let out = "";
  for (const ch of name.toLowerCase()) {
    const idx = from.indexOf(ch);
    out += idx >= 0 ? to[idx] : ch;
  }
  return out.replace(/[^a-z0-9]/g, "");
}

/**
 * Resuelve un lab por MARCA (match_key) — ANA-103. La web no captura ciudad,
 * así que reutiliza cualquier sucursal existente de la marca (typos y
 * variantes de acentos incluidos) y solo inserta cuando la marca es nueva.
 * Ya no depende del unique en `name` (que se retira para permitir
 * sucursales); el backstop de carreras es el unique (match_key, city).
 */
async function upsertLab(name: string | null) {
  if (!name) return null;
  const clean = name.trim();
  if (!clean) return null;

  const supabase = await createServerSupabaseClient();
  const key = normalizeLabMatchKey(clean);

  const { data: existing, error: findError } = await supabase
    .from("labs")
    .select("id")
    .eq("match_key", key)
    .order("id")
    .limit(1);
  if (findError) throw findError;
  if (existing && existing.length > 0) return existing[0].id;

  const { data, error } = await supabase
    .from("labs")
    .insert({ name: clean })
    .select("id")
    .single();

  if (error) {
    // Carrera: otro request creó la marca entre el select y el insert.
    if (error.code === "23505") {
      const { data: raced, error: retryError } = await supabase
        .from("labs")
        .select("id")
        .eq("match_key", key)
        .order("id")
        .limit(1);
      if (retryError) throw retryError;
      if (raced && raced.length > 0) return raced[0].id;
    }
    throw error;
  }
  return data.id;
}

export async function saveRollAction(formData: FormData) {
  const profile = await requireApprovedProfile();
  const code = requiredText(formData, "code");
  const originalCode = text(formData, "originalCode");

  if (originalCode) {
    await updateRoll(profile, originalCode, formData);
  } else {
    await createRoll(profile, code, formData);
  }

  revalidatePath("/dashboard");
  revalidatePath(`/rolls/${encodeURIComponent(code)}`);
  redirect(`/rolls/${encodeURIComponent(code)}`);
}

async function createRoll(profile: ApprovedProfile, code: string, formData: FormData) {
  const manufacturer = text(formData, "manufacturer");
  const filmStock = text(formData, "filmStock");
  const iso = toInt(text(formData, "iso"));
  const filmType = toFilmType(text(formData, "filmType"));
  const maker = text(formData, "maker");
  const modelName = text(formData, "modelName");
  const cameraFormat = text(formData, "cameraFormat");
  const cameraType = text(formData, "cameraType");
  const cameraMount = text(formData, "cameraMount");
  const dev = text(formData, "dev");
  const scan = text(formData, "scan");

  const [filmStockId, cameraId, devLabId, scanLabId] = await Promise.all([
    resolveFilmStock(manufacturer, filmStock, iso, filmType),
    upsertCamera(profile.userId, maker, modelName, { format: cameraFormat, type: cameraType, mount: cameraMount }),
    upsertLab(dev),
    upsertLab(scan)
  ]);

  const row: RollInsert = {
    owner_user_id: profile.userId,
    code,
    film_stock_id: filmStockId,
    iso_pushed: toInt(text(formData, "isoPushed")),
    format: formatStorageValue(text(formData, "format")),
    exp_count: toInt(text(formData, "exp")),
    exp_taken: toInt(text(formData, "expTaken")),
    fresh: toFresh(text(formData, "expFresh")),
    push_pull: text(formData, "pushPull"),
    camera_id: cameraId,
    lens_id: null,
    lens: text(formData, "lens"),
    locations: toArray(text(formData, "locations")),
    photo_types: toArray(text(formData, "photoType")),
    tags: toArray(text(formData, "tags")),
    started: toDate(text(formData, "started")),
    finished: toDate(text(formData, "finished")),
    status: text(formData, "status"),
    dev_lab_id: devLabId,
    scan_lab_id: scanLabId,
    rating: toInt(text(formData, "rating")) || 0,
    notes: text(formData, "notes")
  };

  const supabase = await createServerSupabaseClient();
  const { error } = await supabase.from("rolls").upsert(row, { onConflict: "owner_user_id,code" });
  if (error) throw error;
}

/**
 * Guarda solo lo que cambió respecto a lo que el formulario mostró (ver
 * `roll-edit.ts`). Película, cámara y labs se vuelven a buscar solo si cambió
 * su texto, y el enlace al lente solo se cambia por texto si se editó el lente.
 */
async function updateRoll(profile: ApprovedProfile, originalCode: string, formData: FormData) {
  const after = readRollForm(formData);
  const before = parseOriginalValues(formData.get("originalValues")) ?? (await currentFormValues(originalCode));
  const plan = planRollUpdate(changedRollFields(before, after), after);
  const row: RollUpdate = { ...plan.row };

  const [filmStockId, cameraId, devLabId, scanLabId] = await Promise.all([
    plan.film
      ? resolveFilmStock(nullable(after.manufacturer), nullable(after.filmStock), toInt(nullable(after.iso)), toFilmType(nullable(after.filmType)))
      : null,
    plan.camera ? upsertCamera(profile.userId, nullable(after.maker), nullable(after.modelName), plan.cameraDetails) : null,
    plan.dev ? upsertLab(nullable(after.dev)) : null,
    plan.scan ? upsertLab(nullable(after.scan)) : null
  ]);
  if (plan.film) row.film_stock_id = filmStockId;
  if (plan.camera) row.camera_id = cameraId;
  if (plan.dev) row.dev_lab_id = devLabId;
  if (plan.scan) row.scan_lab_id = scanLabId;

  if (Object.keys(row).length === 0) return;

  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("rolls")
    .update(row)
    .eq("owner_user_id", profile.userId)
    .eq("code", originalCode)
    .select("id");

  if (error) throw error;
  // RLS puede filtrar el update a cero filas sin dar error.
  if (!data || data.length !== 1) throw new Error("Could not confirm the roll was saved");
}

/**
 * Para un formulario sin los valores originales (una página abierta antes de
 * este cambio): se comparan contra el rollo guardado. Si no se puede leer, se
 * falla; escribir todo "por si acaso" es justo lo que esto evita.
 */
async function currentFormValues(code: string): Promise<RollFormValues> {
  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase.from("rolls_flat").select("*").eq("#", code).maybeSingle();
  if (error) throw error;
  const roll = data ? mapRollFlatRow(data) : null;
  if (!roll) throw new Error("Roll not found");
  return rollFormDefaults(roll);
}

export async function deleteRollAction(formData: FormData) {
  const profile = await requireApprovedProfile();
  const code = requiredText(formData, "code");
  const supabase = await createServerSupabaseClient();
  const { error } = await supabase
    .from("rolls")
    .delete()
    .eq("owner_user_id", profile.userId)
    .eq("code", code);

  if (error) throw error;

  revalidatePath("/dashboard");
  redirect("/dashboard");
}
