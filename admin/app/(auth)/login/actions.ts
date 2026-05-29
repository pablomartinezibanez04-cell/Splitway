// admin/app/(auth)/login/actions.ts
"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const credentialsSchema = z.object({
  email: z.string().email("Email inválido."),
  password: z.string().min(1, "Introduce la contraseña."),
});

export type SignInState = {
  error?: string;
};

export async function signIn(
  _prev: SignInState,
  formData: FormData,
): Promise<SignInState> {
  const parsed = credentialsSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = await createClient();
  const { data: signInData, error } =
    await supabase.auth.signInWithPassword(parsed.data);

  if (error || !signInData.user) {
    return { error: "Email o contraseña incorrectos." };
  }

  // Role check happens here so the user gets an immediate, in-form
  // error instead of bouncing through the proxy redirect chain — which
  // strips the ?error=forbidden query in soft-navigation flows.
  const { data: profile } = await supabase
    .from("profiles")
    .select("role")
    .eq("id", signInData.user.id)
    .maybeSingle();

  if (profile?.role !== "admin" && profile?.role !== "superadmin") {
    await supabase.auth.signOut();
    return {
      error: "Tu cuenta no tiene acceso al panel de administración.",
    };
  }

  redirect("/");
}
