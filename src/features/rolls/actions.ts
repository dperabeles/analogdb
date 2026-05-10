"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getCurrentAccessProfile } from "@/features/auth/profile";
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

function toInt(value: string | null) {
  if (!value || value === "-") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function toDate(value: string | null) {
  if (!value) return null;
  const clean = value.slice(0, 10);
  return clean.length === 10 ? clean : null;
}

function toArray(value: string | null) {
  if (!value) return [];
  return value
    .split(value.includes("|") ? "|" : ",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function toFresh(value: string | null) {
  if (value === "FRESH") return true;
  if (value === "EXPIRED") return false;
  return null;
}

function toFilmType(value: string | null): FilmType {
  if (value === "COLOR" || value === "B/W" || value === "SLIDE") return value;
  return null;
}

function formatStorageValue(value: string | null) {
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

async function requireApprovedProfile() {
  const { state, profile } = await getCurrentAccessProfile();
  if (state !== "approved" || !profile) {
    throw new Error("Approved session required");
  }
  return profile;
}

async function upsertFilmStock(manufacturerValue: string | null, nameValue: string | null, iso: number | null, type: FilmType) {
  if (!manufacturerValue && !nameValue) return null;

  const manufacturer = manufacturerValue || "";
  const name = nameValue || "";
  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("film_stocks")
    .upsert(
      { manufacturer, name, iso, type, in_catalog: false },
      { onConflict: "manufacturer,name" }
    )
    .select("id")
    .single();

  if (error) throw error;
  return data.id;
}

async function upsertCamera(
  ownerUserId: string,
  maker: string | null,
  model: string | null,
  format: string | null,
  type: string | null,
  mount: string | null
) {
  if (!maker && !model) return null;

  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("cameras")
    .upsert(
      {
        owner_user_id: ownerUserId,
        maker,
        model,
        format,
        type,
        mount
      },
      { onConflict: "owner_user_id,maker,model" }
    )
    .select("id")
    .single();

  if (error) throw error;
  return data.id;
}

async function upsertLab(name: string | null) {
  if (!name) return null;

  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("labs")
    .upsert({ name }, { onConflict: "name" })
    .select("id")
    .single();

  if (error) throw error;
  return data.id;
}

export async function saveRollAction(formData: FormData) {
  const profile = await requireApprovedProfile();
  const code = requiredText(formData, "code");
  const originalCode = text(formData, "originalCode");
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
    upsertFilmStock(manufacturer, filmStock, iso, filmType),
    upsertCamera(profile.userId, maker, modelName, cameraFormat, cameraType, cameraMount),
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
  if (originalCode) {
    const { owner_user_id: _ownerUserId, id: _id, created_at: _createdAt, ...updateRow } = row;
    const { error } = await supabase
      .from("rolls")
      .update(updateRow satisfies RollUpdate)
      .eq("owner_user_id", profile.userId)
      .eq("code", originalCode);

    if (error) throw error;
  } else {
    const { error } = await supabase.from("rolls").upsert(row, { onConflict: "owner_user_id,code" });
    if (error) throw error;
  }

  revalidatePath("/dashboard");
  revalidatePath(`/rolls/${encodeURIComponent(code)}`);
  redirect(`/rolls/${encodeURIComponent(code)}`);
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
