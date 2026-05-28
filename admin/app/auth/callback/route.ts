// admin/app/auth/callback/route.ts
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/**
 * OAuth callback. Supabase redirects here after the user authenticates
 * with Google (or any other provider) with `?code=<one-time-code>`. We
 * exchange the code for a session via the cookie-bound server client
 * (which writes the auth cookies into the response), then send the user
 * to `/`. The proxy (middleware) will pick it up from there and handle
 * the role gate and onboarding redirect.
 */
export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);

  // `request.url` may use the container's bind address (e.g. 0.0.0.0 in
  // Docker dev) instead of the host the browser actually requested.
  // Honor X-Forwarded-* headers when behind a proxy, then fall back to
  // the Host header, then to request.url as last resort. Redirecting to
  // `http://0.0.0.0:3000/...` produces ERR_ADDRESS_INVALID in browsers.
  const forwardedHost = request.headers.get("x-forwarded-host");
  const forwardedProto = request.headers.get("x-forwarded-proto");
  const host = forwardedHost ?? request.headers.get("host") ?? requestUrl.host;
  const proto = forwardedProto ?? requestUrl.protocol.replace(":", "");
  const origin = `${proto}://${host}`;

  const code = requestUrl.searchParams.get("code");
  const errorDescription = requestUrl.searchParams.get("error_description");

  if (errorDescription || !code) {
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
