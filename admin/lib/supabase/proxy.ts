// admin/lib/supabase/proxy.ts
// Helper invoked by `admin/proxy.ts` (the Next.js 16 proxy convention,
// formerly `middleware.ts`). Refreshes the Supabase session cookie and
// applies the admin role + profile completeness gates.
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "./database.types";

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Touching getUser forces a session refresh.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const pathname = request.nextUrl.pathname;
  const isAuthRoute = pathname.startsWith("/login");
  const isCallbackRoute = pathname.startsWith("/auth/callback");
  const isOnboardingRoute = pathname.startsWith("/onboarding");

  // The OAuth callback handler must run regardless of session state — it's
  // what *creates* the session. Let it through untouched.
  if (isCallbackRoute) {
    return response;
  }

  if (!user && !isAuthRoute) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/login";
    return NextResponse.redirect(redirectUrl);
  }

  if (user && !isAuthRoute) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role, nickname, date_of_birth")
      .eq("id", user.id)
      .maybeSingle();

    const role = profile?.role;
    if (role !== "admin" && role !== "superadmin") {
      await supabase.auth.signOut();
      const redirectUrl = request.nextUrl.clone();
      redirectUrl.pathname = "/login";
      redirectUrl.searchParams.set("error", "forbidden");
      return NextResponse.redirect(redirectUrl);
    }

    const hasNickname = !!profile?.nickname && profile.nickname.trim() !== "";
    const hasDob = !!profile?.date_of_birth;
    // `user.identities` is not reliable: Supabase's updateUser({ password })
    // sets auth.users.encrypted_password but does NOT add an "email"
    // identity for users who originally signed up via OAuth. We instead
    // call a SECURITY DEFINER function (migration 20260528000005) that
    // reads encrypted_password directly under auth.uid().
    const { data: hasPasswordResult } = await supabase.rpc(
      "user_has_password",
    );
    const hasPassword = hasPasswordResult === true;
    const isComplete = hasNickname && hasDob && hasPassword;

    if (!isComplete && !isOnboardingRoute) {
      const redirectUrl = request.nextUrl.clone();
      redirectUrl.pathname = "/onboarding/complete-profile";
      return NextResponse.redirect(redirectUrl);
    }

    if (isComplete && isOnboardingRoute) {
      const redirectUrl = request.nextUrl.clone();
      redirectUrl.pathname = "/";
      return NextResponse.redirect(redirectUrl);
    }
  }

  if (user && isAuthRoute) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/";
    return NextResponse.redirect(redirectUrl);
  }

  return response;
}
