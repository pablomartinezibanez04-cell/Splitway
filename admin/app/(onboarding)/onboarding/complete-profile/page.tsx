// admin/app/(onboarding)/complete-profile/page.tsx
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth";
import { CompleteProfileForm } from "./complete-profile-form";

export default async function CompleteProfilePage() {
  const admin = await requireAdmin();

  const supabase = await createClient();
  const { data: profile } = await supabase
    .from("profiles")
    .select("nickname, date_of_birth")
    .eq("id", admin.id)
    .maybeSingle();

  return (
    <CompleteProfileForm
      currentNickname={profile?.nickname ?? ""}
      currentDateOfBirth={profile?.date_of_birth ?? ""}
    />
  );
}
