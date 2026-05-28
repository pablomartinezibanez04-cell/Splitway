// admin/app/(onboarding)/complete-profile/actions.ts
"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

const schema = z
  .object({
    nickname: z
      .string()
      .trim()
      .min(2, "Mínimo 2 caracteres.")
      .max(24, "Máximo 24 caracteres."),
    dateOfBirth: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/, "Fecha inválida."),
    password: z.string().min(8, "Mínimo 8 caracteres."),
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, {
    path: ["confirm"],
    message: "Las contraseñas no coinciden.",
  })
  .refine(
    (v) => {
      const dob = new Date(v.dateOfBirth);
      if (Number.isNaN(dob.getTime())) return false;
      const today = new Date();
      const minDate = new Date(
        today.getFullYear() - 13,
        today.getMonth(),
        today.getDate(),
      );
      return dob <= minDate;
    },
    { path: ["dateOfBirth"], message: "Debes tener al menos 13 años." },
  );

export type OnboardingState = { error?: string };

export async function completeOnboarding(
  _prev: OnboardingState,
  formData: FormData,
): Promise<OnboardingState> {
  const admin = await requireAdmin();

  const parsed = schema.safeParse({
    nickname: formData.get("nickname"),
    dateOfBirth: formData.get("dateOfBirth"),
    password: formData.get("password"),
    confirm: formData.get("confirm"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = await createClient();

  // Upsert profile: the row already exists for any admin (they were
  // promoted from an existing user, or seeded via SQL). `upsert` is
  // defensive against the corner case where it somehow doesn't.
  const { error: profileErr } = await supabase
    .from("profiles")
    .upsert(
      {
        id: admin.id,
        nickname: parsed.data.nickname,
        date_of_birth: parsed.data.dateOfBirth,
        nickname_changed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "id" },
    );
  if (profileErr) {
    return { error: "No se pudo guardar el perfil." };
  }

  // Set the password on the auth user. updateUser uses the cookie-bound
  // session, so the user must be signed in (they are — middleware lets
  // them through to /onboarding/* with a valid session).
  const { error: passErr } = await supabase.auth.updateUser({
    password: parsed.data.password,
  });
  if (passErr) {
    return { error: "No se pudo establecer la contraseña." };
  }

  await writeAuditLog({
    adminId: admin.id,
    action: "complete_profile",
    targetType: "user",
    targetId: admin.id,
    details: { fieldsSet: ["nickname", "date_of_birth", "password"] },
  });

  redirect("/");
}
