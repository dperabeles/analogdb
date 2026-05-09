"use client";

import { createBrowserClient } from "@supabase/ssr";
import { assertPublicEnv, publicEnv } from "@/lib/env";
import type { Database } from "@/types/database";

export function createBrowserSupabaseClient() {
  assertPublicEnv();

  return createBrowserClient<Database>(
    publicEnv.supabaseUrl,
    publicEnv.supabaseAnonKey
  );
}
