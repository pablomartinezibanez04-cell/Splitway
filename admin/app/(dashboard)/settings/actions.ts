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
    details: { email: admin.email, nickname: admin.nickname },
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

  // Look the user up directly in auth.users via a SECURITY DEFINER RPC.
  // auth.admin.listUsers is capped at perPage=1000 and was returning
  // false negatives once the user base grew past that.
  const { data: targetUserId, error: lookupErr } = await supabase.rpc(
    "find_user_id_by_email",
    { p_email: parsed.data.email },
  );
  if (lookupErr) return { error: "No se pudo consultar usuarios." };
  if (!targetUserId) {
    return { error: "No existe ningún usuario con ese email." };
  }

  const { data: existing } = await supabase
    .from("profiles")
    .select("role, nickname")
    .eq("id", targetUserId)
    .maybeSingle();
  if (!existing) {
    return {
      error:
        "Ese usuario aún no tiene perfil — debe abrir la app móvil al menos una vez antes de poder ser promovido.",
    };
  }
  if (existing.role === "superadmin") {
    return { error: "No se puede modificar el rol de un superadmin." };
  }
  if (existing.role === "admin") {
    return { error: "Este usuario ya es administrador." };
  }

  const { error: updateErr } = await supabase
    .from("profiles")
    .update({ role: "admin" })
    .eq("id", targetUserId);
  if (updateErr) return { error: "No se pudo actualizar el perfil." };

  await writeAuditLog({
    adminId: superadmin.id,
    action: "promote_admin",
    targetType: "user",
    targetId: targetUserId,
    details: {
      targetEmail: parsed.data.email,
      targetNickname: existing.nickname,
      oldRole: "user",
      newRole: "admin",
      actorEmail: superadmin.email,
    },
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
    .select("role, nickname")
    .eq("id", parsed.data.userId)
    .maybeSingle();
  if (current?.role === "superadmin") {
    return { error: "No se puede degradar a otro superadmin." };
  }

  const { data: targetEmail } = await supabase.rpc(
    "find_email_by_user_id",
    { p_user_id: parsed.data.userId },
  );

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
    details: {
      targetEmail: targetEmail ?? null,
      targetNickname: current?.nickname ?? null,
      oldRole: "admin",
      newRole: "user",
      actorEmail: superadmin.email,
    },
  });

  revalidatePath("/settings");
  return { ok: true };
}
