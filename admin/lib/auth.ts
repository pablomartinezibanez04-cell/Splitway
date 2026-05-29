// admin/lib/auth.ts
import "server-only";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AdminRole = "admin" | "superadmin";

export type AdminProfile = {
  id: string;
  email: string;
  nickname: string;
  role: AdminRole;
};

/**
 * Returns the signed-in admin or superadmin profile. Redirects to
 * /login (or /login?error=forbidden) when the caller is not an admin.
 *
 * Middleware already gates the panel at the request level; this helper
 * is defense-in-depth for Server Components and Server Actions and
 * gives callers a typed profile they can rely on.
 */
export async function requireAdmin(): Promise<AdminProfile> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("nickname, role")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError) {
    console.error("[requireAdmin] profiles query failed", profileError.message);
    redirect("/login");
  }

  const role = profile?.role;
  if (role !== "admin" && role !== "superadmin") {
    redirect("/login?error=forbidden");
  }

  return {
    id: user.id,
    // email is always present for email/password admins; the fallback only
    // applies to phone-only or anonymous Supabase users, which this panel
    // does not create.
    email: user.email ?? "",
    nickname: profile?.nickname ?? "",
    role,
  };
}

/**
 * Like requireAdmin but rejects plain admins. Used by superadmin-only
 * actions (promote/demote, delete user).
 */
export async function requireSuperadmin(): Promise<
  AdminProfile & { role: "superadmin" }
> {
  const admin = await requireAdmin();
  if (admin.role !== "superadmin") {
    redirect("/login?error=forbidden");
  }
  return admin as AdminProfile & { role: "superadmin" };
}
