import { createServerSupabaseClient } from "@/lib/supabase/server";

export type AccessState = "public" | "pending" | "approved" | "rejected" | "invalid";

export type AccessProfile = {
  userId: string;
  email: string;
  displayName: string | null;
  status: AccessState;
};

export async function getCurrentAccessProfile() {
  const supabase = await createServerSupabaseClient();
  const {
    data: { user },
    error: userError
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return { state: "public" as const, profile: null };
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("user_id,email,display_name,status")
    .eq("user_id", user.id)
    .maybeSingle();

  if (profileError || !profile) {
    return { state: "invalid" as const, profile: null };
  }

  const state = profile.status as AccessState;
  if (!["pending", "approved", "rejected"].includes(state)) {
    return { state: "invalid" as const, profile: null };
  }

  return {
    state,
    profile: {
      userId: profile.user_id,
      email: profile.email,
      displayName: profile.display_name,
      status: state
    } satisfies AccessProfile
  };
}
