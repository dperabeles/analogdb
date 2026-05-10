import { getCurrentAccessProfile } from "@/features/auth/profile";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database";

export type CameraItem = Database["public"]["Tables"]["cameras"]["Row"] & {
  rollCount: number;
};

export type LensItem = Database["public"]["Tables"]["lenses"]["Row"] & {
  rollCount: number;
};

export type EquipmentOverview = {
  cameras: CameraItem[];
  lenses: LensItem[];
  error: string | null;
};

function countById(rows: { camera_id: number | null; lens_id: number | null }[]) {
  const cameraCounts = new Map<number, number>();
  const lensCounts = new Map<number, number>();

  for (const row of rows) {
    if (row.camera_id) cameraCounts.set(row.camera_id, (cameraCounts.get(row.camera_id) || 0) + 1);
    if (row.lens_id) lensCounts.set(row.lens_id, (lensCounts.get(row.lens_id) || 0) + 1);
  }

  return { cameraCounts, lensCounts };
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
      .select("camera_id,lens_id")
      .eq("owner_user_id", profile.userId)
  ]);

  const error = cameras.error || lenses.error || rolls.error;
  if (error) return { cameras: [], lenses: [], error: error.message };

  const { cameraCounts, lensCounts } = countById(rolls.data || []);

  return {
    cameras: (cameras.data || []).map((camera) => ({
      ...camera,
      rollCount: cameraCounts.get(camera.id) || 0
    })),
    lenses: (lenses.data || []).map((lens) => ({
      ...lens,
      rollCount: lensCounts.get(lens.id) || 0
    })),
    error: null
  };
}
