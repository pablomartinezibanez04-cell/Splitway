# Admin Panel — Phase F2 (Auth Gate) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restrict the admin panel to users whose `profiles.role` is `admin` or `superadmin`, ship the `admin_audit_log` table + writer helper, and build the `/settings` page where any admin can change their own password and superadmins can promote/demote other admins.

**Architecture:** Role checks happen in two places: (1) middleware queries `profiles.role` on every request, signs the user out and redirects to `/login?error=forbidden` when not admin; (2) `requireAdmin()` / `requireSuperadmin()` helpers run inside Server Components and Server Actions for defense-in-depth and to return the typed admin profile. Every mutating action calls `writeAuditLog(...)` via the `service_role` client after the change succeeds. The `(dashboard)` layout gains a sidebar (Inicio / Configuración) and a topbar (admin email + sign-out) so `/settings` is reachable.

**Tech Stack:** Inherited from F1 — Next.js 16, React 19, TypeScript strict, Tailwind CSS v4, shadcn/ui, `@supabase/ssr`, `@supabase/supabase-js`, Zod, pnpm 11. Adds shadcn components: `tabs`, `table`, `separator`, `badge`, `alert-dialog`.

**Branch:** Continue on `feat/admin-panel` (where F1 + Docker landed). F2 commits go on the same branch.

**Out of scope for F2 (handled in later phases):**
- Audit log viewer UI (F8 / hardening) — F2 writes entries, no read-back UI.
- User CRUD (ban, reset password, delete) — F3.
- Route / session / log viewers — F4–F6.
- Dashboard KPIs and charts — F7.
- Vitest / Playwright tests — per spec §9, F1 also has no tests; the same convention applies until F8 introduces critical-flow E2E.

**Acceptance criteria (verified at the final task, in the browser):**
1. Signing in with a non-admin Supabase user (role `user`) lands on `/login?error=forbidden` with a visible message, the session is cleared, and revisiting `/` redirects to `/login` again.
2. Signing in as the seeded superadmin lands on `/`. The new sidebar shows **Inicio** and **Configuración**; the topbar shows the admin email and a **Cerrar sesión** button that works.
3. `/settings` renders with two tabs: **Mi cuenta** and **Administradores**.
4. From **Mi cuenta**, submitting a new password updates the auth user and shows a success toast.
5. From **Administradores**, the superadmin sees every user with role `admin` or `superadmin`, plus a "Promover a admin" form (email input) that turns a `user` into `admin`, and per-row **Demote** / **Promote** controls. Each successful action inserts a row in `admin_audit_log` (verified via SQL).
6. Logged in as a plain `admin` (not `superadmin`), the **Administradores** tab is read-only — no promote/demote controls render and the Server Actions reject the request server-side if called.

---

## File Structure

**New files (created by this plan):**

```
admin/
├── lib/
│   ├── auth.ts                                # requireAdmin / requireSuperadmin
│   └── audit.ts                               # writeAuditLog
├── components/
│   ├── ui/                                    # shadcn additions
│   │   ├── tabs.tsx
│   │   ├── table.tsx
│   │   ├── separator.tsx
│   │   ├── badge.tsx
│   │   └── alert-dialog.tsx
│   └── shared/
│       ├── sidebar.tsx                        # client component, navigation
│       └── topbar.tsx                         # server component, email + sign-out
└── app/
    └── (dashboard)/
        └── settings/
            ├── page.tsx                       # tabs shell (server component)
            ├── my-account-form.tsx            # client form (change password)
            ├── admins-tab.tsx                 # server component, list + cards
            ├── promote-form.tsx               # client form (promote by email)
            ├── demote-button.tsx              # client confirm dialog
            └── actions.ts                     # change password + promote/demote
supabase/migrations/
└── 20260528000003_admin_audit_log.sql
```

**Modified files:**

- `admin/lib/supabase/database.types.ts` — regenerated to include `admin_audit_log`.
- `admin/lib/supabase/middleware.ts` — adds role lookup + sign-out + `?error=forbidden`.
- `admin/app/(auth)/login/page.tsx` — reads `searchParams.error` and displays the forbidden message.
- `admin/app/(dashboard)/layout.tsx` — replaces minimal shell with sidebar + topbar.
- `admin/app/(dashboard)/page.tsx` — uses `requireAdmin()`, drops the inline sign-out (now in topbar).

---

## Task 1: Create the `admin_audit_log` migration and push it to the cloud Supabase

**Files:**
- Create: `supabase/migrations/20260528000003_admin_audit_log.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260528000003_admin_audit_log.sql` with exactly:

```sql
-- supabase/migrations/20260528000003_admin_audit_log.sql
-- Audit log for every mutating admin action in the admin panel.

create table if not exists public.admin_audit_log (
  id          uuid primary key default gen_random_uuid(),
  admin_id    uuid not null references auth.users(id) on delete set null,
  action      text not null,
  target_type text not null,
  target_id   text not null,
  details     jsonb,
  created_at  timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx
  on public.admin_audit_log (created_at desc);

create index if not exists admin_audit_log_admin_idx
  on public.admin_audit_log (admin_id, created_at desc);

alter table public.admin_audit_log enable row level security;

-- Admins and superadmins can read the log. Writes only happen via the
-- service_role client from Server Actions, which bypasses RLS, so no
-- insert policy is needed.
drop policy if exists "admins read audit log" on public.admin_audit_log;
create policy "admins read audit log"
  on public.admin_audit_log
  for select
  to authenticated
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid()
        and role in ('admin', 'superadmin')
    )
  );
```

- [ ] **Step 2: Apply the migration to the cloud project**

Run from repo root:

```powershell
supabase db push
```

Expected: `supabase` reports applying `20260528000003_admin_audit_log.sql` and exits 0. If it complains the project is not linked, run `supabase link --project-ref jylteevzapwnovfkxwzc` first.

- [ ] **Step 3: Verify the table exists in the cloud**

Run:

```powershell
supabase db remote query "select table_name from information_schema.tables where table_schema = 'public' and table_name = 'admin_audit_log';"
```

Expected output contains `admin_audit_log`. If the `db remote query` subcommand is not available in your CLI version, open the Supabase Dashboard → SQL Editor and run the same `select` — one row should come back.

- [ ] **Step 4: Commit**

```powershell
git add supabase/migrations/20260528000003_admin_audit_log.sql
git commit -m "feat(db): add admin_audit_log table with RLS"
```

---

## Task 2: Regenerate `database.types.ts` to include `admin_audit_log`

**Files:**
- Modify: `admin/lib/supabase/database.types.ts` (regenerated)

- [ ] **Step 1: Regenerate the types from the linked cloud project**

From repo root:

```powershell
supabase gen types typescript --linked --schema public > admin/lib/supabase/database.types.ts
```

Expected: file is rewritten without errors. Open it and confirm a new entry `admin_audit_log: { Row: ...; Insert: ...; Update: ...; Relationships: [...] }` appears under `public.Tables`.

- [ ] **Step 2: Sanity-check the TypeScript build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: `pnpm build` completes with no type errors. If the build fails because of an unrelated lint warning treated as error, address only the new failures (do not refactor existing F1 code).

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/supabase/database.types.ts
git commit -m "chore(admin): regenerate db types for admin_audit_log"
```

---

## Task 3: `lib/auth.ts` — `requireAdmin` / `requireSuperadmin`

**Files:**
- Create: `admin/lib/auth.ts`

- [ ] **Step 1: Create the helper**

Create `admin/lib/auth.ts` with exactly:

```ts
// admin/lib/auth.ts
import "server-only";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AdminRole = "admin" | "superadmin";

export type AdminProfile = {
  id: string;
  email: string;
  nickname: string;
  role: AdminRole;
};

/**
 * Returns the signed-in admin or superadmin profile. Redirects to
 * /login (or /login?error=forbidden) when the caller is not an admin.
 *
 * Middleware already gates the panel at the request level; this helper
 * is defense-in-depth for Server Components and Server Actions and
 * gives callers a typed profile they can rely on.
 */
export async function requireAdmin(): Promise<AdminProfile> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, nickname, role")
    .eq("id", user.id)
    .maybeSingle();

  const role = profile?.role;
  if (role !== "admin" && role !== "superadmin") {
    redirect("/login?error=forbidden");
  }

  return {
    id: user.id,
    email: user.email ?? "",
    nickname: profile?.nickname ?? "",
    role,
  };
}

/**
 * Like requireAdmin but rejects plain admins. Used by superadmin-only
 * actions (promote/demote, delete user).
 */
export async function requireSuperadmin(): Promise<
  AdminProfile & { role: "superadmin" }
> {
  const admin = await requireAdmin();
  if (admin.role !== "superadmin") {
    redirect("/login?error=forbidden");
  }
  return admin as AdminProfile & { role: "superadmin" };
}
```

- [ ] **Step 2: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. The helper is not imported anywhere yet, so this only verifies types.

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/auth.ts
git commit -m "feat(admin): add requireAdmin and requireSuperadmin helpers"
```

---

## Task 4: `lib/audit.ts` — `writeAuditLog`

**Files:**
- Create: `admin/lib/audit.ts`

- [ ] **Step 1: Create the helper**

Create `admin/lib/audit.ts` with exactly:

```ts
// admin/lib/audit.ts
import "server-only";

import { adminClient } from "@/lib/supabase/admin";

export type AuditTargetType =
  | "user"
  | "route"
  | "session"
  | "free_ride"
  | "speed_session";

export type AuditAction =
  // F2 actions:
  | "promote_admin"
  | "demote_admin"
  | "change_own_password"
  // Reserved for later phases (kept here so the union is stable):
  | "ban_user"
  | "unban_user"
  | "reset_user_password"
  | "delete_user"
  | "edit_route"
  | "mark_route_official"
  | "delete_route"
  | "delete_session";

export type AuditEntry = {
  adminId: string;
  action: AuditAction;
  targetType: AuditTargetType;
  targetId: string;
  details?: Record<string, unknown>;
};

/**
 * Inserts a row into admin_audit_log using the service_role client.
 *
 * Call this from Server Actions AFTER the mutation has succeeded. Audit
 * failures are logged to the server console but never thrown — losing
 * an audit row should not roll back a successful admin action.
 */
export async function writeAuditLog(entry: AuditEntry): Promise<void> {
  const supabase = adminClient();

  const { error } = await supabase.from("admin_audit_log").insert({
    admin_id: entry.adminId,
    action: entry.action,
    target_type: entry.targetType,
    target_id: entry.targetId,
    details: entry.details ?? null,
  });

  if (error) {
    console.error("[audit] failed to write audit entry", {
      entry,
      error: error.message,
    });
  }
}
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
git commit -m "feat(admin): add writeAuditLog helper"
```

---

## Task 5: Role gate in middleware + forbidden message on the login page

**Files:**
- Modify: `admin/lib/supabase/middleware.ts`
- Modify: `admin/app/(auth)/login/page.tsx`

- [ ] **Step 1: Replace the middleware body with the role-aware version**

Open `admin/lib/supabase/middleware.ts`. Replace the entire `updateSession` function with:

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

  if (!user && !isAuthRoute) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/login";
    return NextResponse.redirect(redirectUrl);
  }

  if (user && !isAuthRoute) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
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
  }

  if (user && isAuthRoute) {
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = "/";
    return NextResponse.redirect(redirectUrl);
  }

  return response;
}
```

Leave the imports and the `import type { Database }` line untouched (they already cover everything above).

- [ ] **Step 2: Make the login page read `searchParams.error`**

Replace the entire `admin/app/(auth)/login/page.tsx` with:

```tsx
// admin/app/(auth)/login/page.tsx
"use client";

import { useActionState } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { signIn, type SignInState } from "./actions";

const initialState: SignInState = {};

export default function LoginPage() {
  const [state, formAction, isPending] = useActionState(signIn, initialState);
  const searchParams = useSearchParams();
  const forbidden = searchParams.get("error") === "forbidden";

  return (
    <main className="flex min-h-screen items-center justify-center bg-muted px-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Splitway Admin</CardTitle>
        </CardHeader>
        <CardContent>
          {forbidden ? (
            <p
              role="alert"
              className="mb-4 rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
              aria-live="polite"
            >
              Tu cuenta no tiene acceso al panel de administración.
            </p>
          ) : null}
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
        </CardContent>
      </Card>
    </main>
  );
}
```

- [ ] **Step 3: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. (Smoke verification of the actual gate happens in Task 12.)

- [ ] **Step 4: Commit**

```powershell
git add admin/lib/supabase/middleware.ts admin/app/(auth)/login/page.tsx
git commit -m "feat(admin): gate panel by admin role in middleware"
```

---

## Task 6: Install the shadcn components needed for the topbar/sidebar and `/settings`

**Files:**
- Create: `admin/components/ui/tabs.tsx`
- Create: `admin/components/ui/table.tsx`
- Create: `admin/components/ui/separator.tsx`
- Create: `admin/components/ui/badge.tsx`
- Create: `admin/components/ui/alert-dialog.tsx`

- [ ] **Step 1: Add the components via the shadcn CLI**

From repo root:

```powershell
cd admin
pnpm dlx shadcn@latest add tabs table separator badge alert-dialog --yes
cd ..
```

Expected: five new files appear under `admin/components/ui/`. The CLI may also add Radix peer dependencies to `package.json`; that is expected. Do not edit the generated files.

- [ ] **Step 2: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/components/ui/ admin/package.json admin/pnpm-lock.yaml
git commit -m "feat(admin): add shadcn tabs, table, separator, badge, alert-dialog"
```

---

## Task 7: Build the dashboard sidebar + topbar shell

**Files:**
- Create: `admin/components/shared/sidebar.tsx`
- Create: `admin/components/shared/topbar.tsx`
- Modify: `admin/app/(dashboard)/layout.tsx`

- [ ] **Step 1: Create the sidebar (client component for active-link styling)**

Create `admin/components/shared/sidebar.tsx`:

```tsx
// admin/components/shared/sidebar.tsx
"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Home, Settings } from "lucide-react";

const NAV_ITEMS = [
  { href: "/", label: "Inicio", icon: Home },
  { href: "/settings", label: "Configuración", icon: Settings },
] as const;

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="hidden w-56 shrink-0 border-r bg-background md:flex md:flex-col">
      <div className="flex h-14 items-center border-b px-4 font-semibold">
        Splitway Admin
      </div>
      <nav className="flex-1 space-y-1 p-2 text-sm">
        {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
          const active =
            href === "/" ? pathname === "/" : pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              className={
                "flex items-center gap-2 rounded-md px-3 py-2 transition-colors " +
                (active
                  ? "bg-accent text-accent-foreground"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground")
              }
            >
              <Icon className="h-4 w-4" />
              {label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
```

- [ ] **Step 2: Create the topbar (server component, signs out via Server Action)**

Create `admin/components/shared/topbar.tsx`:

```tsx
// admin/components/shared/topbar.tsx
import { Button } from "@/components/ui/button";
import { signOut } from "@/app/(dashboard)/actions";
import type { AdminProfile } from "@/lib/auth";

export function Topbar({ admin }: { admin: AdminProfile }) {
  return (
    <header className="flex h-14 items-center justify-between border-b px-4">
      <div className="text-sm text-muted-foreground">
        <span className="font-medium text-foreground">{admin.email}</span>
        <span className="ml-2 rounded-md bg-muted px-2 py-0.5 text-xs">
          {admin.role}
        </span>
      </div>
      <form action={signOut}>
        <Button type="submit" variant="outline" size="sm">
          Cerrar sesión
        </Button>
      </form>
    </header>
  );
}
```

- [ ] **Step 3: Replace the dashboard layout with the new shell**

Replace `admin/app/(dashboard)/layout.tsx` with:

```tsx
// admin/app/(dashboard)/layout.tsx
import { Sidebar } from "@/components/shared/sidebar";
import { Topbar } from "@/components/shared/topbar";
import { requireAdmin } from "@/lib/auth";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const admin = await requireAdmin();

  return (
    <div className="flex min-h-screen bg-background">
      <Sidebar />
      <div className="flex flex-1 flex-col">
        <Topbar admin={admin} />
        <main className="flex-1 p-6">{children}</main>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 5: Commit**

```powershell
git add admin/components/shared/ admin/app/(dashboard)/layout.tsx
git commit -m "feat(admin): dashboard sidebar + topbar shell with role gate"
```

---

## Task 8: Simplify the dashboard home page (the layout now owns the gate)

**Files:**
- Modify: `admin/app/(dashboard)/page.tsx`

- [ ] **Step 1: Replace the home page with a layout-aware version**

Replace `admin/app/(dashboard)/page.tsx` with:

```tsx
// admin/app/(dashboard)/page.tsx
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { requireAdmin } from "@/lib/auth";

export default async function DashboardHome() {
  const admin = await requireAdmin();

  return (
    <Card className="mx-auto max-w-2xl">
      <CardHeader>
        <CardTitle>Bienvenido</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p className="text-sm text-muted-foreground">
          Sesión iniciada como{" "}
          <span className="font-medium">{admin.email}</span> (
          <span className="font-medium">{admin.role}</span>).
        </p>
        <p className="text-sm text-muted-foreground">
          El dashboard real con métricas se construye en la fase F7. Mientras
          tanto, usa <span className="font-medium">Configuración</span> en la
          barra lateral para gestionar administradores.
        </p>
      </CardContent>
    </Card>
  );
}
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
git add admin/app/(dashboard)/page.tsx
git commit -m "refactor(admin): dashboard home uses requireAdmin and topbar sign-out"
```

---

## Task 9: `/settings` tabs shell

**Files:**
- Create: `admin/app/(dashboard)/settings/page.tsx`

(Tasks 10 and 11 create the inner `my-account-form.tsx`, `admins-tab.tsx`, and `actions.ts` files. This task only creates the tabs shell that imports them — so we will reference those files here and import them once they exist.)

- [ ] **Step 1: Create the settings page**

Create `admin/app/(dashboard)/settings/page.tsx`:

```tsx
// admin/app/(dashboard)/settings/page.tsx
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { requireAdmin } from "@/lib/auth";
import { MyAccountForm } from "./my-account-form";
import { AdminsTab } from "./admins-tab";

export default async function SettingsPage() {
  const admin = await requireAdmin();

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Configuración</h1>
        <p className="text-sm text-muted-foreground">
          Gestiona tu cuenta y los administradores del panel.
        </p>
      </div>

      <Tabs defaultValue="account" className="space-y-4">
        <TabsList>
          <TabsTrigger value="account">Mi cuenta</TabsTrigger>
          <TabsTrigger value="admins">Administradores</TabsTrigger>
        </TabsList>

        <TabsContent value="account">
          <MyAccountForm />
        </TabsContent>

        <TabsContent value="admins">
          <AdminsTab currentAdmin={admin} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
```

- [ ] **Step 2: Skip build verification until Tasks 10 + 11 land**

The page imports two files that do not exist yet. **Do not run `pnpm build` after this step alone — it will fail.** The build will be re-verified at the end of Task 11.

- [ ] **Step 3: Commit**

```powershell
git add admin/app/(dashboard)/settings/page.tsx
git commit -m "feat(admin): settings page tab shell (pending child components)"
```

---

## Task 10: "Mi cuenta" — change own password

**Files:**
- Create: `admin/app/(dashboard)/settings/my-account-form.tsx`
- Create: `admin/app/(dashboard)/settings/actions.ts` (with only `changeOwnPassword` for now; admin actions added in Task 11)

- [ ] **Step 1: Create the change-password Server Action**

Create `admin/app/(dashboard)/settings/actions.ts`:

```ts
// admin/app/(dashboard)/settings/actions.ts
"use server";

import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { requireAdmin } from "@/lib/auth";
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
  });

  return { ok: true };
}
```

- [ ] **Step 2: Create the client form that calls it**

Create `admin/app/(dashboard)/settings/my-account-form.tsx`:

```tsx
// admin/app/(dashboard)/settings/my-account-form.tsx
"use client";

import { useActionState, useEffect, useRef } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  changeOwnPassword,
  type ChangePasswordState,
} from "./actions";

const initialState: ChangePasswordState = {};

export function MyAccountForm() {
  const [state, formAction, isPending] = useActionState(
    changeOwnPassword,
    initialState,
  );
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (state.ok) {
      toast.success("Contraseña actualizada.");
      formRef.current?.reset();
    }
  }, [state]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Cambiar contraseña</CardTitle>
      </CardHeader>
      <CardContent>
        <form ref={formRef} action={formAction} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="password">Nueva contraseña</Label>
            <Input
              id="password"
              name="password"
              type="password"
              autoComplete="new-password"
              required
              minLength={8}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="confirm">Confirmar contraseña</Label>
            <Input
              id="confirm"
              name="confirm"
              type="password"
              autoComplete="new-password"
              required
              minLength={8}
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
          <Button type="submit" disabled={isPending}>
            {isPending ? "Guardando…" : "Guardar"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 3: Skip build until Task 11**

`admin-tab.tsx` is still missing — the build will fail. Continue to Task 11.

- [ ] **Step 4: Commit**

```powershell
git add admin/app/(dashboard)/settings/my-account-form.tsx admin/app/(dashboard)/settings/actions.ts
git commit -m "feat(admin): settings 'Mi cuenta' change-password form"
```

---

## Task 11: "Administradores" — list, promote, demote

**Files:**
- Create: `admin/app/(dashboard)/settings/admins-tab.tsx`
- Modify: `admin/app/(dashboard)/settings/actions.ts` (append `promoteAdmin` / `demoteAdmin`)

- [ ] **Step 1: Extend `actions.ts` with promote/demote**

Open `admin/app/(dashboard)/settings/actions.ts`. First, update the import block at the top of the file so it reads exactly:

```ts
"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin, requireSuperadmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";
```

Then append the following at the end of the file (do **not** repeat the import lines that already moved up):

```ts
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

  // Look the user up by email via the auth admin API.
  const { data: list, error: listErr } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (listErr) return { error: "No se pudo consultar usuarios." };

  const target = list.users.find(
    (u) => u.email?.toLowerCase() === parsed.data.email.toLowerCase(),
  );
  if (!target) return { error: "No existe ningún usuario con ese email." };

  const { error: updateErr } = await supabase
    .from("profiles")
    .update({ role: "admin" })
    .eq("id", target.id);
  if (updateErr) return { error: "No se pudo actualizar el perfil." };

  await writeAuditLog({
    adminId: superadmin.id,
    action: "promote_admin",
    targetType: "user",
    targetId: target.id,
    details: { email: target.email, newRole: "admin" },
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
    .select("role")
    .eq("id", parsed.data.userId)
    .maybeSingle();
  if (current?.role === "superadmin") {
    return { error: "No se puede degradar a otro superadmin." };
  }

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
    details: { newRole: "user" },
  });

  revalidatePath("/settings");
  return { ok: true };
}
```

The final file therefore contains: the consolidated imports block, the `changeOwnPassword` action from Task 10, and the new `promoteAdmin` / `demoteAdmin` actions appended at the end.

- [ ] **Step 2: Create the admins tab UI**

Create `admin/app/(dashboard)/settings/admins-tab.tsx`:

```tsx
// admin/app/(dashboard)/settings/admins-tab.tsx
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { adminClient } from "@/lib/supabase/admin";
import type { AdminProfile } from "@/lib/auth";
import { PromoteForm } from "./promote-form";
import { DemoteButton } from "./demote-button";

export async function AdminsTab({
  currentAdmin,
}: {
  currentAdmin: AdminProfile;
}) {
  const supabase = adminClient();
  const { data: admins } = await supabase
    .from("profiles")
    .select("id, nickname, role")
    .in("role", ["admin", "superadmin"])
    .order("role", { ascending: true })
    .order("nickname", { ascending: true });

  // Pull emails via the auth admin API (profiles only stores ids).
  const { data: usersList } = await supabase.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  const emailById = new Map(
    usersList?.users.map((u) => [u.id, u.email ?? "—"]) ?? [],
  );

  const isSuperadmin = currentAdmin.role === "superadmin";

  return (
    <div className="space-y-6">
      {isSuperadmin ? (
        <Card>
          <CardHeader>
            <CardTitle>Promover a admin</CardTitle>
          </CardHeader>
          <CardContent>
            <PromoteForm />
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Administradores actuales</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nickname</TableHead>
                <TableHead>Email</TableHead>
                <TableHead>Rol</TableHead>
                {isSuperadmin ? (
                  <TableHead className="w-24 text-right">Acciones</TableHead>
                ) : null}
              </TableRow>
            </TableHeader>
            <TableBody>
              {(admins ?? []).map((a) => (
                <TableRow key={a.id}>
                  <TableCell className="font-medium">
                    {a.nickname || "—"}
                  </TableCell>
                  <TableCell>{emailById.get(a.id) ?? "—"}</TableCell>
                  <TableCell>
                    <Badge variant={a.role === "superadmin" ? "default" : "secondary"}>
                      {a.role}
                    </Badge>
                  </TableCell>
                  {isSuperadmin ? (
                    <TableCell className="text-right">
                      {a.role === "admin" && a.id !== currentAdmin.id ? (
                        <DemoteButton userId={a.id} nickname={a.nickname} />
                      ) : null}
                    </TableCell>
                  ) : null}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
```

- [ ] **Step 3: Create the promote form (client component)**

Create `admin/app/(dashboard)/settings/promote-form.tsx`:

```tsx
// admin/app/(dashboard)/settings/promote-form.tsx
"use client";

import { useActionState, useEffect, useRef } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { promoteAdmin, type PromoteState } from "./actions";

const initialState: PromoteState = {};

export function PromoteForm() {
  const [state, formAction, isPending] = useActionState(
    promoteAdmin,
    initialState,
  );
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (state.ok) {
      toast.success("Usuario promovido a admin.");
      formRef.current?.reset();
    }
  }, [state]);

  return (
    <form ref={formRef} action={formAction} className="flex items-end gap-3">
      <div className="flex-1 space-y-2">
        <Label htmlFor="promote-email">Email del usuario</Label>
        <Input
          id="promote-email"
          name="email"
          type="email"
          autoComplete="off"
          required
        />
      </div>
      <Button type="submit" disabled={isPending}>
        {isPending ? "Promoviendo…" : "Promover"}
      </Button>
      {state.error ? (
        <p
          role="alert"
          className="ml-3 text-sm text-destructive"
          aria-live="polite"
        >
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
```

- [ ] **Step 4: Create the demote button with confirmation (client component)**

Create `admin/app/(dashboard)/settings/demote-button.tsx`:

```tsx
// admin/app/(dashboard)/settings/demote-button.tsx
"use client";

import { useActionState, useEffect } from "react";
import { toast } from "sonner";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { demoteAdmin, type PromoteState } from "./actions";

const initialState: PromoteState = {};

export function DemoteButton({
  userId,
  nickname,
}: {
  userId: string;
  nickname: string;
}) {
  const [state, formAction, isPending] = useActionState(
    demoteAdmin,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Admin degradado a usuario.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline" size="sm">
          Degradar
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Degradar a {nickname || "usuario"}</AlertDialogTitle>
          <AlertDialogDescription>
            Perderá el acceso al panel de administración. Esta acción se puede
            revertir promoviéndolo de nuevo.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="userId" value={userId} />
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Degradando…" : "Degradar"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}
```

- [ ] **Step 5: Verify the build passes end-to-end**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. All settings imports now resolve.

- [ ] **Step 6: Commit**

```powershell
git add admin/app/(dashboard)/settings/
git commit -m "feat(admin): settings 'Administradores' list with promote/demote"
```

---

## Task 12: Manual end-to-end verification

**Files:** none (verification only).

This task is run **by a human** (or by the controller agent reviewing screenshots). Do not mark steps complete without actually performing them.

- [ ] **Step 1: Start the dev server**

From `admin/`:

```powershell
docker compose up
```

(Or `pnpm dev` if Docker is unavailable.) Wait for `Ready in ...` and open `http://localhost:3000`.

- [ ] **Step 2: Verify the superadmin path (acceptance criteria 2, 3, 4, 5)**

1. Sign in as `pabmariba@gmail.com` (seeded superadmin).
2. Confirm you land on `/`. The sidebar shows **Inicio** + **Configuración**. The topbar shows your email and a `superadmin` badge.
3. Click **Cerrar sesión** → expect to be redirected to `/login`. Sign back in.
4. Click **Configuración**. Confirm the page has two tabs: **Mi cuenta** and **Administradores**.
5. Open **Mi cuenta**, enter a new password (twice), submit → expect a green "Contraseña actualizada." toast.
6. Open **Administradores**. Confirm the "Promover a admin" card is visible. Type an existing non-admin user email and submit → expect a "Usuario promovido a admin." toast and the user appears in the table below with the `admin` badge.
7. In the table, click **Degradar** on the user you just promoted, confirm the dialog → expect the row's role to return to invisible (removed from the list) and a success toast.
8. From a SQL client / Supabase Dashboard SQL editor, run:

   ```sql
   select action, target_type, target_id, details, created_at
   from public.admin_audit_log
   order by created_at desc
   limit 10;
   ```

   Confirm rows exist for `change_own_password`, `promote_admin`, and `demote_admin` from this session.

- [ ] **Step 3: Verify the forbidden path (acceptance criterion 1)**

1. In another browser profile (or incognito) sign in with a regular Supabase user (role `user`).
2. Expect: redirect to `/login?error=forbidden` with the red "Tu cuenta no tiene acceso al panel de administración." banner. The browser DevTools → Application → Cookies tab should show the supabase auth cookies cleared.
3. Try navigating to `/settings` directly → still redirected to `/login`.

- [ ] **Step 4: Verify the admin-only path (acceptance criterion 6)**

1. While signed in as the superadmin, promote a second test user to `admin`.
2. Sign out, sign back in as that `admin`.
3. Open `/settings → Administradores`. Confirm: no "Promover a admin" card, no "Degradar" buttons in the table — the page is read-only.
4. (Optional) From DevTools console, try calling the Server Action directly — it should reject with a redirect to `/login?error=forbidden`.

- [ ] **Step 5: Done**

All acceptance criteria pass → F2 is complete. No commit; this task only checks behavior.

---

## Notes for the executor

- **No tests in this phase.** Per spec §9, only pure helpers + critical E2E get automated tests. Everything in F2 calls Supabase; Vitest mocks of supabase-js are explicitly disallowed. Playwright is deferred to F8.
- **`supabase db push` requires the project to be linked.** If `supabase status` shows it isn't, run `supabase link --project-ref jylteevzapwnovfkxwzc` and re-run.
- **Cloud-only workflow.** There is no local Supabase running. Every migration goes through `supabase db push`, every type regeneration uses `--linked`.
- **Audit log writes never block.** `writeAuditLog` logs to the server console on failure but never throws — a successful admin action must not be rolled back because the audit table is unreachable.
- **`requireAdmin` redirects, never throws.** Callers can use the return value unconditionally because the function never returns when access is denied.
