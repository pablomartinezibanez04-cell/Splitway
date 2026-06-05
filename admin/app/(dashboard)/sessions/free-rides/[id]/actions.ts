// admin/app/(dashboard)/sessions/free-rides/[id]/actions.ts
"use server";

import "server-only";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

const schema = z.object({
  freeRideId: z.string().regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "ID inválido.",
  ),
});

export type DeleteState = { error?: string };

export async function deleteFreeRide(
  _prev: DeleteState,
  formData: FormData,
): Promise<DeleteState> {
  const admin = await requireAdmin();
  const parsed = schema.safeParse({ freeRideId: formData.get("freeRideId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }
  const supabase = adminClient();

  const { data: doomed } = await supabase
    .from("free_rides")
    .select("owner_id, started_at, name")
    .eq("id", parsed.data.freeRideId)
    .maybeSingle();

  const { error } = await supabase
    .from("free_rides")
    .delete()
    .eq("id", parsed.data.freeRideId);
  if (error) return { error: "No se pudo eliminar la salida." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_session",
    targetType: "session",
    targetId: parsed.data.freeRideId,
    details: {
      actorEmail: admin.email,
      type: "free_ride",
      ownerId: doomed?.owner_id,
      startedAt: doomed?.started_at,
      name: doomed?.name,
    },
  });

  revalidatePath("/sessions");
  redirect("/sessions?tab=free-rides");
}
