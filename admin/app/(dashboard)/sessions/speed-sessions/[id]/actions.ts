// admin/app/(dashboard)/sessions/speed-sessions/[id]/actions.ts
"use server";

import "server-only";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

const schema = z.object({
  speedSessionId: z.string().regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "ID inválido.",
  ),
});

export type DeleteState = { error?: string };

export async function deleteSpeedSession(
  _prev: DeleteState,
  formData: FormData,
): Promise<DeleteState> {
  const admin = await requireAdmin();
  const parsed = schema.safeParse({
    speedSessionId: formData.get("speedSessionId"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }
  const supabase = adminClient();

  const { data: doomed } = await supabase
    .from("speed_sessions")
    .select("user_id, name, created_at")
    .eq("id", parsed.data.speedSessionId)
    .maybeSingle();

  // Use soft-delete: speed_sessions has deleted_at, the view filters it out.
  const { error } = await supabase
    .from("speed_sessions")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", parsed.data.speedSessionId);
  if (error) return { error: "No se pudo eliminar la sesión." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_session",
    targetType: "session",
    targetId: parsed.data.speedSessionId,
    details: {
      actorEmail: admin.email,
      type: "speed_session",
      userId: doomed?.user_id,
      name: doomed?.name,
      createdAt: doomed?.created_at,
    },
  });

  revalidatePath("/sessions");
  redirect("/sessions?tab=speed-sessions");
}
