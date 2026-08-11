"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database";

type CameraInsert = Database["public"]["Tables"]["cameras"]["Insert"];
type CameraUpdate = Database["public"]["Tables"]["cameras"]["Update"];
type LensInsert = Database["public"]["Tables"]["lenses"]["Insert"];
type LensUpdate = Database["public"]["Tables"]["lenses"]["Update"];

function text(formData: FormData, key: string) {
  const value = String(formData.get(key) || "").trim();
  return value || null;
}

function requiredText(formData: FormData, key: string) {
  const value = text(formData, key);
  if (!value) throw new Error(`${key} is required`);
  return value;
}

/// Normaliza una marca a Capitalización de Título: PENTAX / pentax / PeNtAx
/// → Pentax.
///
/// Esta web guardaba la marca de cámara con `.toUpperCase()` mientras la app
/// móvil la guarda con el casing canónico de su lista de vocabulario
/// ("Pentax"). Resultado: la MISMA marca vivía como dos valores distintos y
/// cualquier métrica cruzada entre usuarios contaba Pentax y PENTAX por
/// separado. Encima no se veía, porque la app pinta la marca en mayúsculas al
/// mostrarla. Los lentes se salvaron de casualidad: su acción nunca tuvo el
/// `.toUpperCase()` — y por eso están limpios.
///
/// El MODELO no se toca: ahí el casing tiene significado ("OM-1N", "500 C/M").
function normalizeMaker(value: string) {
  return value
    .split(/\s+/)
    .map((word) =>
      word ? word[0].toLocaleUpperCase("es") + word.slice(1).toLocaleLowerCase("es") : word
    )
    .join(" ");
}

function idValue(formData: FormData, key: string) {
  const value = text(formData, key);
  if (!value) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) ? parsed : null;
}

function checked(formData: FormData, key: string) {
  return formData.get(key) === "on";
}

async function requireApprovedProfile() {
  const { state, profile } = await getCurrentAccessProfile();
  if (state !== "approved" || !profile) {
    throw new Error("Approved session required");
  }
  return profile;
}

async function equipmentUsage(ownerUserId: string, column: "camera_id" | "lens_id", id: number) {
  const supabase = await createServerSupabaseClient();
  const { count, error } = await supabase
    .from("rolls")
    .select("id", { count: "exact", head: true })
    .eq("owner_user_id", ownerUserId)
    .eq(column, id);

  if (error) throw error;
  return count || 0;
}

export async function saveCameraAction(formData: FormData) {
  const profile = await requireApprovedProfile();
  const id = idValue(formData, "cameraId");
  const row: CameraInsert = {
    owner_user_id: profile.userId,
    maker: normalizeMaker(requiredText(formData, "maker")),
    model: requiredText(formData, "model"),
    format: requiredText(formData, "format"),
    type: text(formData, "type"),
    mount: text(formData, "mount"),
    supports_interchangeable_lenses: checked(formData, "supportsInterchangeableLenses"),
    show_in_quick_mode: checked(formData, "showInQuickMode")
  };

  const supabase = await createServerSupabaseClient();
  if (id) {
    const updateRow: CameraUpdate = {
      maker: row.maker,
      model: row.model,
      format: row.format,
      type: row.type,
      mount: row.mount,
      supports_interchangeable_lenses: row.supports_interchangeable_lenses,
      show_in_quick_mode: row.show_in_quick_mode
    };
    const { error } = await supabase
      .from("cameras")
      .update(updateRow)
      .eq("owner_user_id", profile.userId)
      .eq("id", id);
    if (error) throw error;
  } else {
    const { error } = await supabase.from("cameras").upsert(row, { onConflict: "owner_user_id,maker,model" });
    if (error) throw error;
  }

  revalidatePath("/equipment");
  revalidatePath("/dashboard");
}

export async function saveLensAction(formData: FormData) {
  const profile = await requireApprovedProfile();
  const id = idValue(formData, "lensId");
  const row: LensInsert = {
    owner_user_id: profile.userId,
    maker: normalizeMaker(requiredText(formData, "maker")),
    model: requiredText(formData, "model"),
    mount: requiredText(formData, "mount"),
    show_in_quick_mode: checked(formData, "showInQuickMode")
  };

  const supabase = await createServerSupabaseClient();
  if (id) {
    const updateRow: LensUpdate = {
      maker: row.maker,
      model: row.model,
      mount: row.mount,
      show_in_quick_mode: row.show_in_quick_mode
    };
    const { error } = await supabase
      .from("lenses")
      .update(updateRow)
      .eq("owner_user_id", profile.userId)
      .eq("id", id);
    if (error) throw error;
  } else {
    const { error } = await supabase.from("lenses").upsert(row, { onConflict: "owner_user_id,maker,model,mount" });
    if (error) throw error;
  }

  revalidatePath("/equipment");
  revalidatePath("/dashboard");
}

export async function removeCameraAction(formData: FormData) {
  const profile = await requireApprovedProfile();
  const id = idValue(formData, "cameraId");
  if (!id) throw new Error("cameraId is required");

  const supabase = await createServerSupabaseClient();
  const usage = await equipmentUsage(profile.userId, "camera_id", id);
  const { error } = usage > 0
    ? await supabase
        .from("cameras")
        .update({ show_in_quick_mode: false })
        .eq("owner_user_id", profile.userId)
        .eq("id", id)
    : await supabase
        .from("cameras")
        .delete()
        .eq("owner_user_id", profile.userId)
        .eq("id", id);

  if (error) throw error;
  revalidatePath("/equipment");
  revalidatePath("/dashboard");
}

export async function removeLensAction(formData: FormData) {
  const profile = await requireApprovedProfile();
  const id = idValue(formData, "lensId");
  if (!id) throw new Error("lensId is required");

  const supabase = await createServerSupabaseClient();
  const usage = await equipmentUsage(profile.userId, "lens_id", id);
  const { error } = usage > 0
    ? await supabase
        .from("lenses")
        .update({ show_in_quick_mode: false })
        .eq("owner_user_id", profile.userId)
        .eq("id", id)
    : await supabase
        .from("lenses")
        .delete()
        .eq("owner_user_id", profile.userId)
        .eq("id", id);

  if (error) throw error;
  revalidatePath("/equipment");
  revalidatePath("/dashboard");
}
