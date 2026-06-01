// admin/app/(dashboard)/routes/[id]/actions.ts
"use server";

import "server-only";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

// ---------- edit metadata ----------

const editSchema = z.object({
  routeId: z.string().uuid(),
  name: z.string().trim().min(1).max(120),
  description: z.string().max(2000).nullable(),
  difficulty: z.enum(["easy", "medium", "hard", "extreme"]),
  locationLabel: z.string().max(200).nullable(),
});

export type EditRouteState = { error?: string; ok?: boolean };

export async function editRoute(
  _prev: EditRouteState,
  formData: FormData,
): Promise<EditRouteState> {
  const admin = await requireAdmin();

  const parsed = editSchema.safeParse({
    routeId: formData.get("routeId"),
    name: formData.get("name"),
    description: formData.get("description") || null,
    difficulty: formData.get("difficulty"),
    locationLabel: formData.get("locationLabel") || null,
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { data: before } = await supabase
    .from("route_templates")
    .select("name, description, difficulty, location_label")
    .eq("id", parsed.data.routeId)
    .maybeSingle();

  const { error } = await supabase
    .from("route_templates")
    .update({
      name: parsed.data.name,
      description: parsed.data.description,
      difficulty: parsed.data.difficulty,
      location_label: parsed.data.locationLabel,
      updated_at: new Date().toISOString(),
    })
    .eq("id", parsed.data.routeId);
  if (error) return { error: "No se pudo guardar la ruta." };

  await writeAuditLog({
    adminId: admin.id,
    action: "edit_route",
    targetType: "route",
    targetId: parsed.data.routeId,
    details: {
      actorEmail: admin.email,
      before,
      after: {
        name: parsed.data.name,
        description: parsed.data.description,
        difficulty: parsed.data.difficulty,
        location_label: parsed.data.locationLabel,
      },
    },
  });

  revalidatePath(`/routes/${parsed.data.routeId}`);
  revalidatePath("/routes");
  return { ok: true };
}

// ---------- toggle is_official ----------

const toggleSchema = z.object({
  routeId: z.string().uuid(),
  isOfficial: z.coerce.boolean(),
});

export type ToggleOfficialState = { error?: string; ok?: boolean };

export async function toggleRouteOfficial(
  _prev: ToggleOfficialState,
  formData: FormData,
): Promise<ToggleOfficialState> {
  const admin = await requireAdmin();

  const rawIsOfficial = formData.get("isOfficial");
  const parsed = toggleSchema.safeParse({
    routeId: formData.get("routeId"),
    isOfficial: rawIsOfficial === "true" || rawIsOfficial === "1",
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { error } = await supabase
    .from("route_templates")
    .update({
      is_official: parsed.data.isOfficial,
      updated_at: new Date().toISOString(),
    })
    .eq("id", parsed.data.routeId);
  if (error) return { error: "No se pudo actualizar la ruta." };

  await writeAuditLog({
    adminId: admin.id,
    action: parsed.data.isOfficial
      ? "mark_route_official"
      : "unmark_route_official",
    targetType: "route",
    targetId: parsed.data.routeId,
    details: {
      actorEmail: admin.email,
      isOfficial: parsed.data.isOfficial,
    },
  });

  revalidatePath(`/routes/${parsed.data.routeId}`);
  revalidatePath("/routes");
  return { ok: true };
}

// ---------- duplicate as official ----------

const duplicateSchema = z.object({ routeId: z.string().uuid() });

export type DuplicateState = { error?: string };

export async function duplicateRouteAsOfficial(
  _prev: DuplicateState,
  formData: FormData,
): Promise<DuplicateState> {
  const admin = await requireAdmin();

  const parsed = duplicateSchema.safeParse({
    routeId: formData.get("routeId"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { data: newId, error } = await supabase.rpc(
    "duplicate_route_as_official",
    { p_source_route_id: parsed.data.routeId, p_admin_id: admin.id },
  );
  if (error || !newId) {
    return { error: "No se pudo duplicar la ruta." };
  }

  await writeAuditLog({
    adminId: admin.id,
    action: "duplicate_route",
    targetType: "route",
    targetId: newId as string,
    details: {
      actorEmail: admin.email,
      sourceRouteId: parsed.data.routeId,
    },
  });

  revalidatePath("/routes");
  redirect(`/routes/${newId}`);
}

// ---------- delete ----------

const deleteSchema = z.object({ routeId: z.string().uuid() });

export type DeleteRouteState = { error?: string };

export async function deleteRoute(
  _prev: DeleteRouteState,
  formData: FormData,
): Promise<DeleteRouteState> {
  const admin = await requireAdmin();

  const parsed = deleteSchema.safeParse({ routeId: formData.get("routeId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();

  const { data: doomed } = await supabase
    .from("route_templates")
    .select("name, owner_id")
    .eq("id", parsed.data.routeId)
    .maybeSingle();

  const { error } = await supabase
    .from("route_templates")
    .delete()
    .eq("id", parsed.data.routeId);
  if (error) return { error: "No se pudo eliminar la ruta." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_route",
    targetType: "route",
    targetId: parsed.data.routeId,
    details: {
      actorEmail: admin.email,
      deletedName: doomed?.name,
      ownerId: doomed?.owner_id,
    },
  });

  revalidatePath("/routes");
  redirect("/routes");
}
