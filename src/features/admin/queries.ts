import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database";

export type AdminProfile = Database["public"]["Tables"]["profiles"]["Row"];
export type AdminRole = Database["public"]["Tables"]["user_roles"]["Row"];
export type AdminAction = Database["public"]["Tables"]["admin_actions"]["Row"];

export type AdminOverview = {
  pending: AdminProfile[];
  approved: AdminProfile[];
  rejected: AdminProfile[];
  roster: AdminRole[];
  actions: AdminAction[];
  error: string | null;
};

export async function getAdminOverview(): Promise<AdminOverview> {
  const supabase = await createServerSupabaseClient();
  const [pending, approved, rejected, roster, actions] = await Promise.all([
    supabase.from("profiles").select("*").eq("status", "pending").order("created_at", { ascending: true }),
    supabase.from("profiles").select("*").eq("status", "approved").order("created_at", { ascending: true }),
    supabase.from("profiles").select("*").eq("status", "rejected").order("created_at", { ascending: true }),
    supabase.from("user_roles").select("user_id, role, is_founder, created_at, granted_by").eq("role", "admin"),
    supabase.from("admin_actions").select("*").order("created_at", { ascending: false })
  ]);

  const error = pending.error || approved.error || rejected.error || roster.error || actions.error;
  if (error) {
    return {
      pending: [],
      approved: [],
      rejected: [],
      roster: [],
      actions: [],
      error: error.message
    };
  }

  return {
    pending: pending.data || [],
    approved: approved.data || [],
    rejected: rejected.data || [],
    roster: roster.data || [],
    actions: actions.data || [],
    error: null
  };
}
