"use server";

import { revalidatePath } from "next/cache";
import { getCurrentAccessProfile } from "@/features/auth/profile";
import { createServerSupabaseClient } from "@/lib/supabase/server";
import type { Database } from "@/types/database";

type ProfileStatus = Database["public"]["Tables"]["profiles"]["Row"]["status"];
type AdminActionType = Database["public"]["Tables"]["admin_actions"]["Row"]["action_type"];
type AdminDecision = Database["public"]["Tables"]["admin_action_approvals"]["Row"]["decision"];

function value(formData: FormData, key: string) {
  return String(formData.get(key) || "").trim();
}

function requireValue(formData: FormData, key: string) {
  const formValue = value(formData, key);
  if (!formValue) throw new Error(`${key} is required`);
  return formValue;
}

function profileStatus(value: string): ProfileStatus {
  if (value === "pending" || value === "approved" || value === "rejected") return value;
  throw new Error("Invalid profile status");
}

function adminActionType(value: string): AdminActionType {
  if (value === "promote_to_admin" || value === "demote_from_admin") return value;
  throw new Error("Invalid admin action type");
}

function adminDecision(value: string): AdminDecision {
  if (value === "approved" || value === "rejected") return value;
  throw new Error("Invalid admin vote decision");
}

async function requireAdminProfile() {
  const { state, profile } = await getCurrentAccessProfile();
  if (state !== "approved" || profile?.role !== "admin") {
    throw new Error("Admin session required");
  }
  return profile;
}

export async function setProfileStatusAction(formData: FormData) {
  await requireAdminProfile();
  const targetUserId = requireValue(formData, "targetUserId");
  const status = profileStatus(requireValue(formData, "status"));
  const supabase = await createServerSupabaseClient();
  const { error } = await supabase.rpc("admin_set_profile_status", {
    p_target_user_id: targetUserId,
    p_status: status
  });

  if (error) throw error;
  revalidatePath("/admin");
  revalidatePath("/dashboard");
}

export async function requestAdminRoleChangeAction(formData: FormData) {
  await requireAdminProfile();
  const targetUserId = requireValue(formData, "targetUserId");
  const actionType = adminActionType(requireValue(formData, "actionType"));
  const supabase = await createServerSupabaseClient();
  const { error } = await supabase.rpc("request_admin_action", {
    p_action_type: actionType,
    p_target_user_id: targetUserId
  });

  if (error) throw error;
  revalidatePath("/admin");
}

export async function voteAdminAction(formData: FormData) {
  await requireAdminProfile();
  const actionId = requireValue(formData, "actionId");
  const decision = adminDecision(requireValue(formData, "decision"));
  const supabase = await createServerSupabaseClient();
  const { error } = await supabase.rpc("cast_admin_action_vote", {
    p_action_id: actionId,
    p_decision: decision
  });

  if (error) throw error;
  revalidatePath("/admin");
  revalidatePath("/dashboard");
}
