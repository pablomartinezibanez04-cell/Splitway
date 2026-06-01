// admin/app/(dashboard)/users/[id]/actions.ts
"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

// ---------- edit profile ----------

const editProfileSchema = z.object({
  userId: z.string().uuid(),
  nickname: z.string().trim().min(2).max(24),
  bio: z.string().max(500).nullable(),
});

export type EditProfileState = { error?: string; ok?: boolean };

export async function editUserProfile(
  _prev: EditProfileState,
  formData: FormData,
): Promise<EditProfileState> {
  const admin = await requireAdmin();

  const parsed = editProfileSchema.safeParse({
    userId: formData.get("userId"),
    nickname: formData.get("nickname"),
    bio: formData.get("bio") || null,
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { data: before } = await supabase
    .from("profiles")
    .select("nickname, bio")
    .eq("id", parsed.data.userId)
    .maybeSingle();

  const { error } = await supabase
    .from("profiles")
    .update({
      nickname: parsed.data.nickname,
      bio: parsed.data.bio,
      updated_at: new Date().toISOString(),
    })
    .eq("id", parsed.data.userId);
  if (error) return { error: "No se pudo guardar el perfil." };

  await writeAuditLog({
    adminId: admin.id,
    action: "edit_user_profile",
    targetType: "user",
    targetId: parsed.data.userId,
    details: {
      actorEmail: admin.email,
      before: { nickname: before?.nickname, bio: before?.bio },
      after: { nickname: parsed.data.nickname, bio: parsed.data.bio },
    },
  });

  revalidatePath(`/users/${parsed.data.userId}`);
  return { ok: true };
}

// ---------- ban / unban ----------

const banSchema = z.object({
  userId: z.string().uuid(),
  durationHours: z.coerce.number().int().positive(),
});

export type BanState = { error?: string; ok?: boolean };

export async function banUser(
  _prev: BanState,
  formData: FormData,
): Promise<BanState> {
  const admin = await requireAdmin();

  const parsed = banSchema.safeParse({
    userId: formData.get("userId"),
    durationHours: formData.get("durationHours"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  if (parsed.data.userId === admin.id) {
    return { error: "No puedes banearte a ti mismo." };
  }

  const supabase = adminClient();
  const { error } = await supabase.auth.admin.updateUserById(
    parsed.data.userId,
    { ban_duration: `${parsed.data.durationHours}h` },
  );
  if (error) return { error: "No se pudo aplicar el ban." };

  await writeAuditLog({
    adminId: admin.id,
    action: "ban_user",
    targetType: "user",
    targetId: parsed.data.userId,
    details: {
      actorEmail: admin.email,
      durationHours: parsed.data.durationHours,
    },
  });

  revalidatePath(`/users/${parsed.data.userId}`);
  revalidatePath("/users");
  return { ok: true };
}

const unbanSchema = z.object({ userId: z.string().uuid() });

export async function unbanUser(
  _prev: BanState,
  formData: FormData,
): Promise<BanState> {
  const admin = await requireAdmin();

  const parsed = unbanSchema.safeParse({ userId: formData.get("userId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { error } = await supabase.auth.admin.updateUserById(
    parsed.data.userId,
    { ban_duration: "none" },
  );
  if (error) return { error: "No se pudo levantar el ban." };

  await writeAuditLog({
    adminId: admin.id,
    action: "unban_user",
    targetType: "user",
    targetId: parsed.data.userId,
    details: { actorEmail: admin.email },
  });

  revalidatePath(`/users/${parsed.data.userId}`);
  revalidatePath("/users");
  return { ok: true };
}

// ---------- reset password ----------

const resetSchema = z.object({
  userId: z.string().uuid(),
  email: z.string().email(),
});

export type ResetState = { error?: string; ok?: boolean };

export async function resetUserPassword(
  _prev: ResetState,
  formData: FormData,
): Promise<ResetState> {
  const admin = await requireAdmin();

  const parsed = resetSchema.safeParse({
    userId: formData.get("userId"),
    email: formData.get("email"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  // generateLink with type=recovery sends the password-reset email via
  // Supabase's configured SMTP. The link itself we discard — Supabase
  // emails it to the user as part of the flow.
  const { error } = await supabase.auth.admin.generateLink({
    type: "recovery",
    email: parsed.data.email,
  });
  if (error) return { error: "No se pudo enviar el email de reseteo." };

  await writeAuditLog({
    adminId: admin.id,
    action: "reset_user_password",
    targetType: "user",
    targetId: parsed.data.userId,
    details: {
      actorEmail: admin.email,
      targetEmail: parsed.data.email,
    },
  });

  return { ok: true };
}
