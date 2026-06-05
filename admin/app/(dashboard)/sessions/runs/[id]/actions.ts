// admin/app/(dashboard)/sessions/runs/[id]/actions.ts
"use server";

import "server-only";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

const schema = z.object({
  sessionId: z.string().regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "ID inválido.",
  ),
});

export type DeleteState = { error?: string };

export async function deleteSessionRun(
  _prev: DeleteState,
  formData: FormData,
): Promise<DeleteState> {
  const admin = await requireAdmin();
  const parsed = schema.safeParse({ sessionId: formData.get("sessionId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }
  const supabase = adminClient();

  const { data: doomed } = await supabase
    .from("session_runs")
    .select("owner_id, started_at")
    .eq("id", parsed.data.sessionId)
    .maybeSingle();

  const { error } = await supabase
    .from("session_runs")
    .delete()
    .eq("id", parsed.data.sessionId);
  if (error) return { error: "No se pudo eliminar la sesión." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_session",
    targetType: "session",
    targetId: parsed.data.sessionId,
    details: {
      actorEmail: admin.email,
      type: "session_run",
      ownerId: doomed?.owner_id,
      startedAt: doomed?.started_at,
    },
  });

  revalidatePath("/sessions");
  redirect("/sessions?tab=runs");
}
