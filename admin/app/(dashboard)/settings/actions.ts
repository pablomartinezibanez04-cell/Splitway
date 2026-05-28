// admin/app/(dashboard)/settings/actions.ts
"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin, requireSuperadmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

// ---------- change own password ----------

const passwordSchema = z
  .object({
    password: z.string().min(8, "Mínimo 8 caracteres."),
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, {
    path: ["confirm"],
    message: "Las contraseñas no coinciden.",
  });

export type ChangePasswordState = { error?: string; ok?: boolean };

export async function changeOwnPassword(
  _prev: ChangePasswordState,
  formData: FormData,
): Promise<ChangePasswordState> {
  const admin = await requireAdmin();

  const parsed = passwordSchema.safeParse({
    password: formData.get("password"),
    confirm: formData.get("confirm"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({
    password: parsed.data.password,
  });
  if (error) {
    return { error: "No se pudo actualizar la contraseña." };
  }

  await writeAuditLog({
    adminId: admin.id,
    action: "change_own_password",
    targetType: "user",
    targetId: admin.id,
  });

  return { ok: true };
}

// ---------- promote / demote ----------

const promoteSchema = z.object({
  email: z.string().email("Email inválido."),
});

export type PromoteState = { error?: string; ok?: boolean };

export async function promoteAdmin(
  _prev: PromoteState,
  formData: FormData,
): Promise<PromoteState> {
  const superadmin = await requireSuperadmin();

  const parsed = promoteSchema.safeParse({ email: formData.get("email") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();

  // Look the user up by email via the auth admin API.
  const { data: list, error: listErr } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (listErr) return { error: "No se pudo consultar usuarios." };

  const target = list.users.find(
    (u) => u.email?.toLowerCase() === parsed.data.email.toLowerCase(),
  );
  if (!target) return { error: "No existe ningún usuario con ese email." };

  const { error: updateErr } = await supabase
    .from("profiles")
    .update({ role: "admin" })
    .eq("id", target.id);
  if (updateErr) return { error: "No se pudo actualizar el perfil." };

  await writeAuditLog({
    adminId: superadmin.id,
    action: "promote_admin",
    targetType: "user",
    targetId: target.id,
    details: { email: target.email, newRole: "admin" },
  });

  revalidatePath("/settings");
  return { ok: true };
}

const demoteSchema = z.object({
  userId: z.string().uuid(),
});

export async function demoteAdmin(
  _prev: PromoteState,
  formData: FormData,
): Promise<PromoteState> {
  const superadmin = await requireSuperadmin();

  const parsed = demoteSchema.safeParse({ userId: formData.get("userId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  // Guard: cannot demote yourself (would lock everyone out if you are
  // the last superadmin) and cannot demote a superadmin via this action.
  if (parsed.data.userId === superadmin.id) {
    return { error: "No puedes degradarte a ti mismo." };
  }

  const supabase = adminClient();

  const { data: current } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", parsed.data.userId)
    .maybeSingle();
  if (current?.role === "superadmin") {
    return { error: "No se puede degradar a otro superadmin." };
  }

  const { error: updateErr } = await supabase
    .from("profiles")
    .update({ role: "user" })
    .eq("id", parsed.data.userId);
  if (updateErr) return { error: "No se pudo actualizar el perfil." };

  await writeAuditLog({
    adminId: superadmin.id,
    action: "demote_admin",
    targetType: "user",
    targetId: parsed.data.userId,
    details: { newRole: "user" },
  });

  revalidatePath("/settings");
  return { ok: true };
}
