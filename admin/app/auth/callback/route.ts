// admin/app/auth/callback/route.ts
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * OAuth callback. Supabase redirects here after the user authenticates
 * with Google (or any other provider) with `?code=<one-time-code>`. We
 * exchange the code for a session via the cookie-bound server client
 * (which writes the auth cookies into the response), then send the user
 * to `/`. The middleware will pick it up from there and handle the role
 * gate and onboarding redirect.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const errorDescription = searchParams.get("error_description");

  if (errorDescription) {
    const redirect = new URL("/login", origin);
    redirect.searchParams.set("error", "oauth_failed");
    return NextResponse.redirect(redirect);
  }

  if (!code) {
    const redirect = new URL("/login", origin);
    redirect.searchParams.set("error", "oauth_failed");
    return NextResponse.redirect(redirect);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) {
    const redirect = new URL("/login", origin);
    redirect.searchParams.set("error", "oauth_failed");
    return NextResponse.redirect(redirect);
  }

  return NextResponse.redirect(new URL("/", origin));
}
