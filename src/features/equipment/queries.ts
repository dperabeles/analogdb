import { getCurrentAccessProfile } from "@/features/auth/profile";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database";

export type CameraItem = Database["public"]["Tables"]["cameras"]["Row"] & {
  rollCount: number;
  lastUsed: string | null;
};

export type LensItem = Database["public"]["Tables"]["lenses"]["Row"] & {
  rollCount: number;
  lastUsed: string | null;
};

export type EquipmentOverview = {
  cameras: CameraItem[];
  lenses: LensItem[];
  error: string | null;
};

function effectiveDate(row: { started: string | null; finished: string | null }) {
  return row.finished || row.started || null;
}

function countById(rows: { camera_id: number | null; lens_id: number | null; started: string | null; finished: string | null }[]) {
  const cameraCounts = new Map<number, number>();
  const lensCounts = new Map<number, number>();
  const cameraLastUsed = new Map<number, string>();
  const lensLastUsed = new Map<number, string>();

  for (const row of rows) {
    const used = effectiveDate(row);
    if (row.camera_id) {
      cameraCounts.set(row.camera_id, (cameraCounts.get(row.camera_id) || 0) + 1);
      if (used && used > (cameraLastUsed.get(row.camera_id) || "")) cameraLastUsed.set(row.camera_id, used);
    }
    if (row.lens_id) {
      lensCounts.set(row.lens_id, (lensCounts.get(row.lens_id) || 0) + 1);
      if (used && used > (lensLastUsed.get(row.lens_id) || "")) lensLastUsed.set(row.lens_id, used);
    }
  }

  return { cameraCounts, lensCounts, cameraLastUsed, lensLastUsed };
}

export async function getEquipmentOverview(): Promise<EquipmentOverview> {
  const { state, profile } = await getCurrentAccessProfile();
  if (state !== "approved" || !profile) {
    return { cameras: [], lenses: [], error: "Approved session required" };
  }

  const supabase = await createServerSupabaseClient();
  const [cameras, lenses, rolls] = await Promise.all([
    supabase
      .from("cameras")
      .select("*")
      .eq("owner_user_id", profile.userId)
      .order("maker", { ascending: true })
      .order("model", { ascending: true }),
    supabase
      .from("lenses")
      .select("*")
      .eq("owner_user_id", profile.userId)
      .order("maker", { ascending: true })
      .order("model", { ascending: true }),
    supabase
      .from("rolls")
      .select("camera_id,lens_id,started,finished")
      .eq("owner_user_id", profile.userId)
  ]);

  const error = cameras.error || lenses.error || rolls.error;
  if (error) return { cameras: [], lenses: [], error: error.message };

  const { cameraCounts, lensCounts, cameraLastUsed, lensLastUsed } = countById(rolls.data || []);

  return {
    cameras: (cameras.data || []).map((camera) => ({
      ...camera,
      rollCount: cameraCounts.get(camera.id) || 0,
      lastUsed: cameraLastUsed.get(camera.id) || null
    })),
    lenses: (lenses.data || []).map((lens) => ({
      ...lens,
      rollCount: lensCounts.get(lens.id) || 0,
      lastUsed: lensLastUsed.get(lens.id) || null
    })),
    error: null
  };
}
