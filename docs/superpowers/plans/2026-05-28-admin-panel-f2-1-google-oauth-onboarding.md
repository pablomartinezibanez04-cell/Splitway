# Admin Panel — Phase F2.1 (Google OAuth + Onboarding) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins sign into the panel with Google OAuth and force every admin (regardless of sign-in method) to have a complete profile — `profiles.nickname` + `profiles.date_of_birth` + a password set on `auth.users` — before they reach the dashboard.

**Architecture:** A dedicated `/auth/callback` route exchanges the OAuth code for a session. The existing middleware is extended in two ways: it queries `nickname` and `date_of_birth` alongside `role`, and it consults `user.identities` for an `email` provider entry. If an admin is signed in but any completeness condition fails, middleware redirects to a new `/onboarding/complete-profile` page (its own route group with a minimal layout). The page collects the missing pieces, the Server Action upserts the profile + sets the password via the cookie-bound client + writes an audit log entry.

**Tech Stack:** Inherited from F2 — Next.js 16, `@supabase/ssr`, Zod, shadcn/ui, sonner. No new dependencies, no new migrations.

**Branch:** Continue on `feat/admin-panel`.

**Out of scope for F2.1 (in F2.2 or beyond):**
- Flutter app changes (separate plan `2026-05-28-flutter-f2-2-profile-completeness.md` — to be written when F2.1 lands).
- Backfilling existing incomplete profiles via SQL (enforcement is lazy, fires on next sign-in).
- A DB-side `is_profile_complete` RPC.
- Avatar / bio in the completeness criterion.

**Acceptance criteria (verified in Task 8, in the browser):**
1. The `/login` page shows a "Continuar con Google" button below the existing email+password form.
2. Clicking it sends the user through Google's OAuth flow and back to `/auth/callback`, which exchanges the code for a session.
3. The seeded superadmin (`pabmariba@gmail.com`, Google only, no DOB, no password) lands on `/onboarding/complete-profile` — NOT `/`.
4. The form on that page accepts a nickname (min 2 / max 24 chars, pre-populated with the current value when present), a date of birth (must be ≤ today and at least 13 years ago), and a password (min 8 chars, with confirm). On submit it updates `profiles`, sets the auth password, writes an `admin_audit_log` row with `action = 'complete_profile'`, and redirects to `/`.
5. After completing onboarding, signing out + signing back in with the same email + the new password works.
6. A second admin who is **already** complete (e.g., a test user promoted in F2 with a password set in advance) never sees the onboarding screen.
7. A user with role `user` who signs in via Google is signed out and redirected to `/login?error=forbidden` (F2's forbidden flow is untouched).

---

## File Structure

**New files:**

```
admin/
├── app/
│   ├── auth/
│   │   └── callback/
│   │       └── route.ts                        # OAuth code exchange
│   └── (onboarding)/
│       ├── layout.tsx                          # minimal centered layout
│       └── complete-profile/
│           ├── page.tsx                        # server component, loads current profile
│           ├── complete-profile-form.tsx       # client form
│           └── actions.ts                      # completeOnboarding server action
```

**Modified files:**

- `admin/lib/audit.ts` — add `"complete_profile"` to `AuditAction` union.
- `admin/lib/supabase/middleware.ts` — extend role query, add identities check, add onboarding redirect logic.
- `admin/middleware.ts` — confirm the matcher includes `/auth/callback` (it likely already does via the catch-all).
- `admin/app/(auth)/login/page.tsx` — add a "Continuar con Google" button next to the existing form.

---

## Task 1: Extend `AuditAction` with `complete_profile`

**Files:**
- Modify: `admin/lib/audit.ts`

- [ ] **Step 1: Add the new action**

Open `admin/lib/audit.ts`. Locate the `AuditAction` union (under the `// F2 actions:` comment) and add `"complete_profile"` to the F2 group. The final union should read:

```ts
export type AuditAction =
  // F2 actions:
  | "promote_admin"
  | "demote_admin"
  | "change_own_password"
  | "complete_profile"
  // Reserved for later phases (kept here so the union is stable):
  | "ban_user"
  | "unban_user"
  | "reset_user_password"
  | "delete_user"
  | "edit_route"
  | "mark_route_official"
  | "delete_route"
  | "delete_session";
```

- [ ] **Step 2: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/audit.ts
git commit -m "feat(admin): add complete_profile audit action"
```

---

## Task 2: Create the OAuth callback route handler

**Files:**
- Create: `admin/app/auth/callback/route.ts`

- [ ] **Step 1: Create the route handler**

Create `admin/app/auth/callback/route.ts` with EXACTLY:

```ts
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
```

- [ ] **Step 2: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. The route is reachable at `/auth/callback`.

- [ ] **Step 3: Commit**

```powershell
git add admin/app/auth/callback/route.ts
git commit -m "feat(admin): add /auth/callback OAuth code exchange route"
```

---

## Task 3: Extend the login page with `oauth_failed` error display + Google button

**Files:**
- Modify: `admin/app/(auth)/login/page.tsx`

- [ ] **Step 1: Update the login page**

The page currently has a `ForbiddenBanner` that handles `?error=forbidden`. Extend it to also show a message for `?error=oauth_failed`, and add a "Continuar con Google" button below the form.

Replace `admin/app/(auth)/login/page.tsx` ENTIRELY with:

```tsx
// admin/app/(auth)/login/page.tsx
"use client";

import { Suspense, useActionState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/browser";
import { signIn, type SignInState } from "./actions";

const initialState: SignInState = {};

function LoginBanner() {
  const searchParams = useSearchParams();
  const error = searchParams.get("error");

  if (error === "forbidden") {
    return (
      <p
        role="alert"
        className="mb-4 rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        aria-live="polite"
      >
        Tu cuenta no tiene acceso al panel de administración.
      </p>
    );
  }

  if (error === "oauth_failed") {
    return (
      <p
        role="alert"
        className="mb-4 rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
        aria-live="polite"
      >
        No se pudo completar el inicio de sesión con Google. Inténtalo de nuevo.
      </p>
    );
  }

  return null;
}

function LoginForm() {
  const [state, formAction, isPending] = useActionState(signIn, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          required
        />
      </div>
      <div className="space-y-2">
        <Label htmlFor="password">Contraseña</Label>
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="current-password"
          required
        />
      </div>
      {state.error ? (
        <p
          role="alert"
          className="text-sm text-destructive"
          aria-live="polite"
        >
          {state.error}
        </p>
      ) : null}
      <Button type="submit" className="w-full" disabled={isPending}>
        {isPending ? "Entrando…" : "Entrar"}
      </Button>
    </form>
  );
}

function GoogleButton() {
  async function handleClick() {
    const supabase = createClient();
    await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback`,
      },
    });
  }

  return (
    <Button
      type="button"
      variant="outline"
      className="w-full"
      onClick={handleClick}
    >
      Continuar con Google
    </Button>
  );
}

export default function LoginPage() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-muted px-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Splitway Admin</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Suspense>
            <LoginBanner />
          </Suspense>
          <LoginForm />
          <div className="relative">
            <div className="absolute inset-0 flex items-center">
              <span className="w-full border-t" />
            </div>
            <div className="relative flex justify-center text-xs uppercase">
              <span className="bg-card px-2 text-muted-foreground">o</span>
            </div>
          </div>
          <GoogleButton />
        </CardContent>
      </Card>
    </main>
  );
}
```

Notes:
- The `GoogleButton` is its own client component, but the whole file is already `"use client"` so the same module hosts it.
- `createClient` here is the browser client from `@/lib/supabase/browser` (already created in F1).
- `signInWithOAuth({ provider: "google" })` returns a URL the SDK navigates to — by default it opens Google's consent screen and redirects back to `redirectTo` with `?code=...`.

- [ ] **Step 2: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/app/(auth)/login/page.tsx
git commit -m "feat(admin): add Google sign-in button and oauth_failed error"
```

---

## Task 4: Extend the middleware with completeness check + onboarding redirect

**Files:**
- Modify: `admin/lib/supabase/middleware.ts`

- [ ] **Step 1: Replace the `updateSession` function**

Replace the entire `updateSession` function in `admin/lib/supabase/middleware.ts` with the version below. The imports at the top of the file (`createServerClient`, `NextResponse`, `NextRequest`, `Database` type) stay the same.

```ts
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
    const hasPassword = !!user.identities?.some((i) => i.provider === "email");
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
```

Key changes vs. the F2 version:
- New `isCallbackRoute` short-circuit so `/auth/callback` is never gated.
- The role query now selects `nickname, date_of_birth` too.
- New `hasNickname`, `hasDob`, `hasPassword`, `isComplete` block.
- Two new redirects: incomplete admin → onboarding; complete admin on onboarding → home.

- [ ] **Step 2: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. Behavioral verification is in Task 8 (manual).

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/supabase/middleware.ts
git commit -m "feat(admin): require complete profile in middleware"
```

---

## Task 5: Create the `(onboarding)` route group with a minimal layout

**Files:**
- Create: `admin/app/(onboarding)/layout.tsx`

- [ ] **Step 1: Create the layout**

Create `admin/app/(onboarding)/layout.tsx` with EXACTLY:

```tsx
// admin/app/(onboarding)/layout.tsx
// Minimal layout used by onboarding screens. No sidebar / topbar so a
// signed-in admin with an incomplete profile is not tempted to navigate
// elsewhere — the middleware will bounce them back anyway, but giving
// them no navigation surface is the cleanest UX.
export default function OnboardingLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-muted p-4">
      {children}
    </main>
  );
}
```

- [ ] **Step 2: Verify the build still passes**

The layout has no children pages yet (the next task adds one). Next.js won't complain about empty route groups but will warn about an unused layout. Build should still exit 0.

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/app/(onboarding)/layout.tsx
git commit -m "feat(admin): add onboarding route group with minimal layout"
```

---

## Task 6: Build `/onboarding/complete-profile` (page + form + action)

**Files:**
- Create: `admin/app/(onboarding)/complete-profile/page.tsx`
- Create: `admin/app/(onboarding)/complete-profile/complete-profile-form.tsx`
- Create: `admin/app/(onboarding)/complete-profile/actions.ts`

- [ ] **Step 1: Create the Server Action**

Create `admin/app/(onboarding)/complete-profile/actions.ts` with EXACTLY:

```ts
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
```

- [ ] **Step 2: Create the client form**

Create `admin/app/(onboarding)/complete-profile/complete-profile-form.tsx` with EXACTLY:

```tsx
// admin/app/(onboarding)/complete-profile/complete-profile-form.tsx
"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { completeOnboarding, type OnboardingState } from "./actions";

const initialState: OnboardingState = {};

export function CompleteProfileForm({
  currentNickname,
  currentDateOfBirth,
}: {
  currentNickname: string;
  currentDateOfBirth: string;
}) {
  const [state, formAction, isPending] = useActionState(
    completeOnboarding,
    initialState,
  );

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle>Completa tu perfil</CardTitle>
        <CardDescription>
          Necesitamos algunos datos para terminar de configurar tu cuenta de
          administrador. La contraseña te permitirá iniciar sesión también con
          email.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="nickname">Apodo</Label>
            <Input
              id="nickname"
              name="nickname"
              type="text"
              defaultValue={currentNickname}
              minLength={2}
              maxLength={24}
              autoComplete="nickname"
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="dateOfBirth">Fecha de nacimiento</Label>
            <Input
              id="dateOfBirth"
              name="dateOfBirth"
              type="date"
              defaultValue={currentDateOfBirth}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Contraseña</Label>
            <Input
              id="password"
              name="password"
              type="password"
              autoComplete="new-password"
              minLength={8}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirm">Confirmar contraseña</Label>
            <Input
              id="confirm"
              name="confirm"
              type="password"
              autoComplete="new-password"
              minLength={8}
              required
            />
          </div>
          {state.error ? (
            <p
              role="alert"
              className="text-sm text-destructive"
              aria-live="polite"
            >
              {state.error}
            </p>
          ) : null}
          <Button type="submit" className="w-full" disabled={isPending}>
            {isPending ? "Guardando…" : "Guardar y entrar"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 3: Create the page (server component that pre-loads current values)**

Create `admin/app/(onboarding)/complete-profile/page.tsx` with EXACTLY:

```tsx
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
```

- [ ] **Step 4: Verify the build passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. All onboarding imports resolve.

- [ ] **Step 5: Commit**

```powershell
git add admin/app/(onboarding)/complete-profile/
git commit -m "feat(admin): /onboarding/complete-profile page and action"
```

---

## Task 7: Manual Supabase Dashboard configuration

**Files:** none — manual user step.

The Supabase project must allow `http://localhost:3000/auth/callback` as a post-OAuth redirect destination, otherwise Supabase rejects the callback and the user sees an error from Supabase rather than the panel.

- [ ] **Step 1: Open the dashboard**

Go to <https://supabase.com/dashboard/project/jylteevzapwnovfkxwzc/auth/url-configuration>.

- [ ] **Step 2: Add the dev redirect URL**

Under **Redirect URLs**, add:

```
http://localhost:3000/auth/callback
```

(If you ran the admin panel on a different port, use that one. If/when a production URL is decided, add `<prod-url>/auth/callback` too.)

Save the configuration.

- [ ] **Step 3: Verify Google OAuth is enabled**

Under **Authentication → Providers → Google**, confirm the toggle is on and the Google Client ID + Secret are populated. They must already be (the Flutter app uses Google OAuth), so this is a sanity check.

- [ ] **Step 4: No commit**

This task changes Dashboard config, not code.

---

## Task 8: Manual end-to-end verification

**Files:** none — verification only.

Performed by a human against the live admin panel.

- [ ] **Step 1: Start the dev server**

From `admin/`:

```powershell
docker compose up      # or pnpm dev
```

Open <http://localhost:3000>.

- [ ] **Step 2: Verify the seeded superadmin onboarding (criteria 1–5)**

1. Sign out completely first (clear cookies in DevTools if necessary).
2. On `/login`, confirm the **Continuar con Google** button is visible below the form, with a horizontal "o" divider.
3. Click **Continuar con Google**, pick `pabmariba@gmail.com` in the Google chooser.
4. Expected: brief redirect through `/auth/callback`, then land on `/onboarding/complete-profile` (NOT `/`).
5. The form shows: Apodo (pre-filled with `admin` if that's what the seed used), Fecha de nacimiento (empty), Contraseña, Confirmar contraseña.
6. Fill in a date of birth in the past, set a password (≥8 chars) twice, submit.
7. Expected: redirect to `/`, the dashboard home renders normally with the sidebar + topbar.
8. From the Supabase Dashboard SQL editor:
   ```sql
   select action, target_type, target_id, details, created_at
   from public.admin_audit_log
   where action = 'complete_profile'
   order by created_at desc
   limit 1;
   ```
   Confirm a row exists with `target_id` equal to your user UUID and `details = {"fieldsSet": ["nickname", "date_of_birth", "password"]}`.

- [ ] **Step 3: Verify password sign-in now works (criterion 5)**

1. Click **Cerrar sesión** in the topbar → redirected to `/login`.
2. Enter the same email + the password you just set, submit.
3. Expected: redirect to `/`, dashboard renders, no detour through onboarding.

- [ ] **Step 4: Verify already-complete admins skip onboarding (criterion 6)**

1. While signed in as the superadmin, go to `/settings → Administradores` and promote another existing user to `admin`.
2. From the Supabase dashboard (or via SQL), update that promoted user's profile so `date_of_birth` is populated (since they may not have it):
   ```sql
   update public.profiles set date_of_birth = '1990-01-01' where id = '<their-uuid>';
   ```
   And set a password for them either via the dashboard (Auth → Users → … → "Send password reset") or by having them go through the same onboarding once.
3. Sign in as that user. Expected: lands directly on `/` — never sees `/onboarding/complete-profile`.

- [ ] **Step 5: Verify non-admin Google users still get rejected (criterion 7)**

1. In incognito, sign in via Google with a non-admin account.
2. Expected: redirect to `/login?error=forbidden` with the red banner. The supabase auth cookies are cleared. (Same F2 behavior, just confirming OAuth didn't break it.)

- [ ] **Step 6: Done**

If all five checks pass → F2.1 is complete and F2 verification is unblocked. No commit.

---

## Notes for the executor

- **No new dependencies.** Everything used here (Next.js Server Actions, `@supabase/ssr`, shadcn primitives, sonner) is already in the project from F1/F2.
- **No new migrations.** The completeness contract uses fields that already exist.
- **`signInWithOAuth` opens a full-page redirect** — there's no need to await its promise in the click handler; the browser navigates away. The button doesn't need a loading state.
- **`exchangeCodeForSession` mutates cookies via the SSR client.** That's why the callback route uses `await createClient()` (the cookie-bound one), not `adminClient()`.
- **`upsert` on `profiles`** uses `onConflict: "id"` because the PK is `id`. We pass `nickname_changed_at` so the cooldown is correctly initialized on first profile creation.
- **Audit failures never block.** `writeAuditLog` consumes its own errors. If the audit row fails, the user still completes onboarding and is redirected.
