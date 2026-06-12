// admin/lib/auth.ts
import "server-only";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { adminClient } from "@/lib/supabase/admin";

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

/**
 * Authorizes a destructive action on a target user, enforcing the role
 * hierarchy so a privilege-equal-or-lower actor cannot disrupt a higher one:
 *
 * - Nobody may act on a `superadmin` through these panel actions (a plain
 *   admin must never be able to ban / reset / edit a superadmin and lock them
 *   out — see audit SEC-3).
 * - Only a `superadmin` may act on another `admin`.
 *
 * Returns an `{ error }` to surface in the form, or an empty object when the
 * action is allowed. Uses the service-role client to read the target's role.
 */
export async function authorizeTargetAction(
  targetUserId: string,
  actorRole: AdminRole,
): Promise<{ error?: string }> {
  const supabase = adminClient();
  const { data } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", targetUserId)
    .maybeSingle();

  const targetRole = data?.role;
  if (targetRole === "superadmin") {
    return { error: "No se puede realizar esta acción sobre un superadmin." };
  }
  if (targetRole === "admin" && actorRole !== "superadmin") {
    return {
      error: "Solo un superadmin puede gestionar a otros administradores.",
    };
  }
  return {};
}
