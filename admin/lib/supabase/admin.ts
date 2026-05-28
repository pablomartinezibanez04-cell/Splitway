// admin/lib/supabase/admin.ts
import "server-only";

import { createClient } from "@supabase/supabase-js";
import type { Database } from "./database.types";

/**
 * Privileged Supabase client using the service_role key. RLS does NOT apply.
 *
 * This file imports `server-only`, so any attempt to bundle it into a client
 * component will fail the build. Never import it from a file that runs in the
 * browser.
 *
 * Use it from Server Actions and Server Components that legitimately need
 * cross-user access, AFTER calling the appropriate role guard (added in F2).
 */
export function adminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Missing Supabase admin env vars (NEXT_PUBLIC_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY).",
    );
  }

  return createClient<Database>(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
