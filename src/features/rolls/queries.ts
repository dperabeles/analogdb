import { createServerSupabaseClient } from "@/lib/supabase/server";
import { mapRollFlatRow, type RollListItem } from "@/features/rolls/roll-types";

export type RollQueryResult = {
  rolls: RollListItem[];
  error: string | null;
};

export async function getRolls(): Promise<RollQueryResult> {
  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("rolls_flat")
    .select("*")
    .order("id", { ascending: false });

  if (error) {
    return { rolls: [], error: error.message };
  }

  return {
    rolls: (data || []).map(mapRollFlatRow).filter((roll): roll is RollListItem => roll !== null),
    error: null
  };
}

export async function getRollByCode(code: string): Promise<{ roll: RollListItem | null; error: string | null }> {
  const supabase = await createServerSupabaseClient();
  const { data, error } = await supabase
    .from("rolls_flat")
    .select("*")
    .eq("#", code)
    .maybeSingle();

  if (error) {
    return { roll: null, error: error.message };
  }

  return { roll: data ? mapRollFlatRow(data) : null, error: null };
}
