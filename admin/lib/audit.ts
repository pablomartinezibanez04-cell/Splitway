// admin/lib/audit.ts
import "server-only";

import { adminClient } from "@/lib/supabase/admin";
import type { Json } from "@/lib/supabase/database.types";

export type AuditTargetType =
  | "user"
  | "route"
  | "session"
  | "free_ride"
  | "speed_session";

export type AuditAction =
  // F2 actions:
  | "promote_admin"
  | "demote_admin"
  | "change_own_password"
  // Reserved for later phases (kept here so the union is stable):
  | "ban_user"
  | "unban_user"
  | "reset_user_password"
  | "delete_user"
  | "edit_route"
  | "mark_route_official"
  | "delete_route"
  | "delete_session";

export type AuditEntry = {
  adminId: string;
  action: AuditAction;
  targetType: AuditTargetType;
  targetId: string;
  details?: Record<string, unknown>;
};

/**
 * Inserts a row into admin_audit_log using the service_role client.
 *
 * Call this from Server Actions AFTER the mutation has succeeded. Audit
 * failures are logged to the server console but never thrown — losing
 * an audit row should not roll back a successful admin action.
 */
export async function writeAuditLog(entry: AuditEntry): Promise<void> {
  const supabase = adminClient();

  const { error } = await supabase.from("admin_audit_log").insert({
    admin_id: entry.adminId,
    action: entry.action,
    target_type: entry.targetType,
    target_id: entry.targetId,
    details: (entry.details ?? null) as Json | null,
  });

  if (error) {
    console.error("[audit] failed to write audit entry", {
      entry,
      error: error.message,
    });
  }
}
