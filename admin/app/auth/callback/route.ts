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
/**
 * Resolves the origin to redirect back to after the OAuth exchange.
 *
 * `request.url` may use the container's bind address (e.g. 0.0.0.0 in Docker
 * dev) instead of the host the browser actually requested, so we honor
 * X-Forwarded-* headers. Because those headers are attacker-controllable when
 * a proxy doesn't strip client-supplied values, we validate the resulting
 * host against `ADMIN_ALLOWED_REDIRECT_HOSTS` (comma-separated) when set —
 * this closes the post-login open-redirect (audit SEC-4). When the allowlist
 * is unset (local dev) behavior is unchanged.
 */
function resolveOrigin(request: NextRequest): string {
  const requestUrl = new URL(request.url);
  const forwardedHost = request.headers.get("x-forwarded-host");
  const forwardedProto = request.headers.get("x-forwarded-proto");
  const host = forwardedHost ?? request.headers.get("host") ?? requestUrl.host;
  const proto = forwardedProto ?? requestUrl.protocol.replace(":", "");

  const allowlist = (process.env.ADMIN_ALLOWED_REDIRECT_HOSTS ?? "")
    .split(",")
    .map((h) => h.trim().toLowerCase())
    .filter(Boolean);

  if (allowlist.length > 0 && !allowlist.includes(host.toLowerCase())) {
    // Forwarded host is not trusted — fall back to the first allowed host
    // instead of redirecting to an attacker-controlled domain.
    return `${proto}://${allowlist[0]}`;
  }

  return `${proto}://${host}`;
}

export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);
  const origin = resolveOrigin(request);

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

  // Role check happens here (in addition to the proxy) so non-admin
  // OAuth users land on /login?error=forbidden via a hard navigation
  // that reliably preserves the query string and the banner renders.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();

    if (profile?.role !== "admin" && profile?.role !== "superadmin") {
      await supabase.auth.signOut();
      const redirect = new URL("/login", origin);
      redirect.searchParams.set("error", "forbidden");
      return NextResponse.redirect(redirect);
    }
  }

  return NextResponse.redirect(new URL("/", origin));
}
