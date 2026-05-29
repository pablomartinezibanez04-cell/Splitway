// admin/lib/supabase/server.ts
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "./database.types";

/**
 * Cookie-bound Supabase client for Server Components, Route Handlers,
 * and Server Actions. Uses the public anon key — RLS applies as the
 * signed-in user. For privileged reads/writes use `adminClient` from
 * `./admin`.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // setAll throws when called from a pure Server Component.
            // The middleware refreshes the session, so we can ignore here.
          }
        },
      },
    },
  );
}
