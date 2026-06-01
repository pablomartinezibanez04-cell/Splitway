# Admin Panel — Phase F3 (Users) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/users` user-management surface — a paginated, sortable, filterable list and a tabbed detail page (Profile, Activity, Garage, Routes, Logs) with ban/unban and reset-password actions. Delete-user is explicitly deferred to F8.

**Architecture:** A single SQL view (`admin_users_view`) joins `profiles` + `auth.users` + the per-user counts/last-activity computation so the list page issues one query for everything. TanStack Table v8 drives the client-side rendering with server-side pagination/sort/filter via URL params. Server Components fetch data; Server Actions perform mutations through the existing `adminClient` (service_role); every mutating action writes an `admin_audit_log` entry. Tab content is rendered server-side per request.

**Tech Stack:** Inherited from F2/F2.1 — Next.js 16 App Router, `@supabase/ssr`, `@supabase/supabase-js`, Zod, shadcn/ui, sonner. New: **TanStack Table v8** (`@tanstack/react-table`), **date-fns** (already in spec; used for formatting), **shadcn additions** (skeleton, dropdown-menu, select). No new database tables — one new SQL view + RPCs already shipped in F2/F2.1 are reused.

**Branch:** `feat/admin-users` (already created from `main`).

**Out of scope for F3 (handled later):**
- Delete user action and superadmin-only confirmations for it (**F8 — Hardening**).
- Bulk actions (spec §2 YAGNI).
- CSV export (spec §2 YAGNI).
- Editing other users' email (would require email-change-confirm flow; defer).
- Editing other users' avatar (storage policies are tied to the user's own folder; admin would need a separate code path).
- Virtualized tables for >1000 rows (current user base is small; revisit if logs viewer in F6 needs it).

**Acceptance criteria (verified at Task 17, in the browser):**
1. The sidebar gains a **Usuarios** entry. Clicking it loads `/users` in under a second.
2. The list shows columns: avatar, nickname, email, role, signup date, last activity, sessions count, routes count, status (Activo / Baneado).
3. Pagination works: default 25 rows, switching pages preserves filters and sort via the URL.
4. Free-text search filters by email OR nickname; the input debounces 300ms before issuing a request.
5. Filtering by role (`user` / `admin` / `superadmin`) and status (`active` / `banned`) narrows the list correctly.
6. Sorting by signup date, last activity, sessions count and routes count works in both directions.
7. Clicking a row navigates to `/users/[id]` and shows the user's email, nickname, role badge, and avatar at the top.
8. The five tabs render real data for the chosen user: Perfil (editable), Actividad (combined session list), Garaje (vehicles), Rutas (route_templates), Logs (app_logs paginated).
9. From the Perfil tab, editing nickname or bio and saving updates the row, writes an `edit_user_profile` audit log entry, and shows a success toast. The role selector is visible only to superadmins.
10. From the Danger Zone, banning a user with a chosen duration (1h, 24h, 7d, 30d, permanent) calls `auth.admin.updateUserById({ ban_duration: ... })`, writes a `ban_user` audit entry, and the status column flips to **Baneado** with the unban date.
11. Unbanning resets status to **Activo** and writes an `unban_user` audit entry.
12. Resetting a user's password sends them the Supabase password-reset email and writes a `reset_user_password` audit entry; a success toast confirms the email was sent.
13. A plain `admin` (not superadmin) sees the role selector hidden on Perfil and cannot promote/demote roles from the detail page (still uses /settings for that). All other actions work.

---

## File Structure

**New files:**

```
admin/
├── app/(dashboard)/users/
│   ├── page.tsx                              # list page (Server Component)
│   ├── users-table.tsx                       # client TanStack Table
│   ├── filters-bar.tsx                       # client filters (search + role + status)
│   ├── pagination.tsx                        # client pager (Prev/Next + page size)
│   └── [id]/
│       ├── page.tsx                          # detail Server Component (header + Tabs)
│       ├── actions.ts                        # editProfile + ban + unban + resetPassword
│       ├── profile-tab.tsx                   # client form
│       ├── activity-tab.tsx                  # server component
│       ├── garage-tab.tsx                    # server component
│       ├── routes-tab.tsx                    # server component
│       ├── logs-tab.tsx                      # server component
│       ├── ban-dialog.tsx                    # client confirm dialog
│       └── reset-password-dialog.tsx         # client confirm dialog
├── components/ui/                            # shadcn additions (generated)
│   ├── skeleton.tsx
│   ├── dropdown-menu.tsx
│   └── select.tsx
├── lib/users/
│   └── search-params.ts                      # parse + serialize ?page=&sort=&search=...
supabase/migrations/
└── 20260528000008_admin_users_view.sql       # joined view + grant
```

**Modified files:**

- `admin/components/shared/sidebar.tsx` — add `/users` link with the Users lucide icon.
- `admin/lib/audit.ts` — extend `AuditAction` union with `edit_user_profile`, `ban_user`, `unban_user`, `reset_user_password`.
- `admin/lib/supabase/database.types.ts` — regenerated to include the new view.
- `admin/package.json` + `admin/pnpm-lock.yaml` — add `@tanstack/react-table` and `date-fns`.

---

## Task 1: SQL view `admin_users_view`

**Files:**
- Create: `supabase/migrations/20260528000008_admin_users_view.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260528000008_admin_users_view.sql` with EXACTLY:

```sql
-- supabase/migrations/20260528000008_admin_users_view.sql
-- One-shot read for the admin panel's /users list. Joins profiles with
-- auth.users (for email, signup date, ban status) and computes per-user
-- aggregates so the list page can sort/filter without N+1 queries.
--
-- Service-role only. Granted explicitly because views default to
-- inheriting privileges from underlying tables; auth.users would
-- otherwise be off-limits to lower roles.

create or replace view public.admin_users_view as
select
  p.id,
  p.nickname,
  p.avatar_url,
  p.role,
  p.created_at as profile_created_at,
  u.email,
  u.created_at as signup_date,
  u.banned_until,
  greatest(
    coalesce(
      (select max(started_at) from public.session_runs where owner_id = p.id),
      'epoch'::timestamptz
    ),
    coalesce(
      (select max(started_at) from public.free_rides where owner_id = p.id),
      'epoch'::timestamptz
    ),
    coalesce(
      (select max(created_at) from public.speed_sessions where user_id = p.id),
      'epoch'::timestamptz
    )
  ) as last_activity,
  (
    coalesce((select count(*) from public.session_runs where owner_id = p.id), 0) +
    coalesce((select count(*) from public.free_rides where owner_id = p.id), 0) +
    coalesce((select count(*) from public.speed_sessions where user_id = p.id), 0)
  ) as sessions_count,
  coalesce(
    (select count(*) from public.route_templates where owner_id = p.id),
    0
  ) as routes_count
from public.profiles p
left join auth.users u on u.id = p.id;

revoke all on public.admin_users_view from public, anon, authenticated;
grant select on public.admin_users_view to service_role;
```

- [ ] **Step 2: Apply to cloud**

```powershell
supabase db push
```

Expected: applies `20260528000008_admin_users_view.sql`, exits 0.

- [ ] **Step 3: Verify**

In the Supabase Dashboard SQL editor:
```sql
select id, nickname, email, role, signup_date, last_activity, sessions_count, routes_count
from public.admin_users_view
order by signup_date desc
limit 5;
```

Confirm rows return and all columns are populated as expected (your superadmin row at minimum).

- [ ] **Step 4: Commit**

```powershell
git add supabase/migrations/20260528000008_admin_users_view.sql
git commit -m "feat(db): admin_users_view for /users list page"
```

---

## Task 2: Regenerate `database.types.ts`

**Files:**
- Modify (regenerate): `admin/lib/supabase/database.types.ts`

- [ ] **Step 1: Regenerate types**

```powershell
supabase gen types typescript --linked --schema public 2>$null > admin/lib/supabase/database.types.ts
```

Expected: the file is rewritten and now contains a `Views: { admin_users_view: { Row: {...} } }` block under `public`.

- [ ] **Step 2: Verify the build still passes**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/supabase/database.types.ts
git commit -m "chore(admin): regenerate types for admin_users_view"
```

---

## Task 3: Install TanStack Table + date-fns

**Files:**
- Modify: `admin/package.json`
- Modify: `admin/pnpm-lock.yaml`

- [ ] **Step 1: Install**

```powershell
cd admin
pnpm add @tanstack/react-table date-fns
cd ..
```

Expected: `pnpm` adds both packages to `dependencies`, updates the lockfile.

- [ ] **Step 2: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/package.json admin/pnpm-lock.yaml
git commit -m "feat(admin): add @tanstack/react-table and date-fns"
```

---

## Task 4: Add shadcn components (skeleton, dropdown-menu, select)

**Files:**
- Create: `admin/components/ui/skeleton.tsx`
- Create: `admin/components/ui/dropdown-menu.tsx`
- Create: `admin/components/ui/select.tsx`

- [ ] **Step 1: Add via shadcn CLI**

```powershell
cd admin
pnpm dlx shadcn@latest add skeleton dropdown-menu select --yes
cd ..
```

Expected: three new files in `admin/components/ui/`. Radix peers may get added to `package.json` — that's fine.

- [ ] **Step 2: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/components/ui/ admin/package.json admin/pnpm-lock.yaml
git commit -m "feat(admin): add shadcn skeleton, dropdown-menu, select"
```

---

## Task 5: Extend `AuditAction` union for F3 actions

**Files:**
- Modify: `admin/lib/audit.ts`

- [ ] **Step 1: Update the union**

Open `admin/lib/audit.ts`. The `AuditAction` union currently has F2/F2.1 entries followed by a "Reserved for later phases" block. Move `ban_user`, `unban_user`, `reset_user_password` from the reserved block into the F3 block, and add `edit_user_profile`:

```ts
export type AuditAction =
  // F2 actions:
  | "promote_admin"
  | "demote_admin"
  | "change_own_password"
  | "complete_profile"
  // F3 actions:
  | "edit_user_profile"
  | "ban_user"
  | "unban_user"
  | "reset_user_password"
  // Reserved for later phases (kept here so the union is stable):
  | "delete_user"
  | "edit_route"
  | "mark_route_official"
  | "delete_route"
  | "delete_session";
```

- [ ] **Step 2: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/audit.ts
git commit -m "feat(admin): F3 audit actions in union"
```

---

## Task 6: Sidebar entry for `/users`

**Files:**
- Modify: `admin/components/shared/sidebar.tsx`

- [ ] **Step 1: Add the nav item**

Open `admin/components/shared/sidebar.tsx`. The file has a `NAV_ITEMS` constant with two entries (`/` Inicio, `/settings` Configuración). Add a `Users` icon import from `lucide-react` and a new entry between them:

Replace the existing `NAV_ITEMS` block with:

```tsx
import { Home, Settings, Users } from "lucide-react";

const NAV_ITEMS = [
  { href: "/", label: "Inicio", icon: Home },
  { href: "/users", label: "Usuarios", icon: Users },
  { href: "/settings", label: "Configuración", icon: Settings },
] as const;
```

Keep the rest of the file unchanged.

- [ ] **Step 2: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/components/shared/sidebar.tsx
git commit -m "feat(admin): sidebar entry for /users"
```

---

## Task 7: URL search params parser

**Files:**
- Create: `admin/lib/users/search-params.ts`

This is the shared helper that the list page and the filters/pager use to read/write URL state in a typed way.

- [ ] **Step 1: Create the helper**

Create `admin/lib/users/search-params.ts` with EXACTLY:

```ts
// admin/lib/users/search-params.ts
import "server-only";

export type RoleFilter = "all" | "user" | "admin" | "superadmin";
export type StatusFilter = "all" | "active" | "banned";
export type SortKey =
  | "signup_date"
  | "last_activity"
  | "sessions_count"
  | "routes_count"
  | "nickname";
export type SortDir = "asc" | "desc";

export type UsersQuery = {
  page: number;
  pageSize: number;
  search: string;
  role: RoleFilter;
  status: StatusFilter;
  sort: SortKey;
  dir: SortDir;
};

const DEFAULTS: UsersQuery = {
  page: 1,
  pageSize: 25,
  search: "",
  role: "all",
  status: "all",
  sort: "signup_date",
  dir: "desc",
};

const ROLES: readonly RoleFilter[] = ["all", "user", "admin", "superadmin"];
const STATUSES: readonly StatusFilter[] = ["all", "active", "banned"];
const SORTS: readonly SortKey[] = [
  "signup_date",
  "last_activity",
  "sessions_count",
  "routes_count",
  "nickname",
];
const DIRS: readonly SortDir[] = ["asc", "desc"];

function pickOne<T extends string>(
  raw: string | undefined,
  allowed: readonly T[],
  fallback: T,
): T {
  if (!raw) return fallback;
  return (allowed as readonly string[]).includes(raw) ? (raw as T) : fallback;
}

export function parseUsersQuery(
  searchParams: Record<string, string | string[] | undefined>,
): UsersQuery {
  const raw = (key: string): string | undefined => {
    const v = searchParams[key];
    return Array.isArray(v) ? v[0] : v;
  };
  const pageRaw = Number.parseInt(raw("page") ?? "", 10);
  const pageSizeRaw = Number.parseInt(raw("pageSize") ?? "", 10);
  return {
    page: Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : DEFAULTS.page,
    pageSize:
      [25, 50, 100].includes(pageSizeRaw)
        ? pageSizeRaw
        : DEFAULTS.pageSize,
    search: (raw("search") ?? DEFAULTS.search).slice(0, 100),
    role: pickOne(raw("role"), ROLES, DEFAULTS.role),
    status: pickOne(raw("status"), STATUSES, DEFAULTS.status),
    sort: pickOne(raw("sort"), SORTS, DEFAULTS.sort),
    dir: pickOne(raw("dir"), DIRS, DEFAULTS.dir),
  };
}

/** Build a URL search-params string from a partial UsersQuery override. */
export function serializeUsersQuery(
  current: UsersQuery,
  override: Partial<UsersQuery>,
): string {
  const merged: UsersQuery = { ...current, ...override };
  const params = new URLSearchParams();
  if (merged.page !== DEFAULTS.page) params.set("page", String(merged.page));
  if (merged.pageSize !== DEFAULTS.pageSize) {
    params.set("pageSize", String(merged.pageSize));
  }
  if (merged.search !== DEFAULTS.search) params.set("search", merged.search);
  if (merged.role !== DEFAULTS.role) params.set("role", merged.role);
  if (merged.status !== DEFAULTS.status) params.set("status", merged.status);
  if (merged.sort !== DEFAULTS.sort) params.set("sort", merged.sort);
  if (merged.dir !== DEFAULTS.dir) params.set("dir", merged.dir);
  const s = params.toString();
  return s ? `?${s}` : "";
}
```

- [ ] **Step 2: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/users/search-params.ts
git commit -m "feat(admin): URL search-params parser for /users"
```

---

## Task 8: `/users` list page — data fetching shell

**Files:**
- Create: `admin/app/(dashboard)/users/page.tsx`

This task creates the Server Component that fetches data. The `UsersTable`, `FiltersBar`, and `Pagination` it references are created in Tasks 9, 10, 11 — analyze will error until then. **Do NOT run `pnpm build` after this task** — only the final F3 build verification after Task 11 needs to pass.

- [ ] **Step 1: Create the page**

Create `admin/app/(dashboard)/users/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/page.tsx
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { parseUsersQuery } from "@/lib/users/search-params";
import { FiltersBar } from "./filters-bar";
import { UsersTable } from "./users-table";
import { Pagination } from "./pagination";

export const dynamic = "force-dynamic";

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const admin = await requireAdmin();
  const q = parseUsersQuery(await searchParams);
  const supabase = adminClient();

  let query = supabase
    .from("admin_users_view")
    .select("*", { count: "exact" });

  if (q.search.trim() !== "") {
    const term = `%${q.search.trim()}%`;
    query = query.or(`email.ilike.${term},nickname.ilike.${term}`);
  }
  if (q.role !== "all") {
    query = query.eq("role", q.role);
  }
  if (q.status === "active") {
    query = query.or("banned_until.is.null,banned_until.lt.now()");
  }
  if (q.status === "banned") {
    query = query.gt("banned_until", new Date().toISOString());
  }

  query = query.order(q.sort, { ascending: q.dir === "asc" });
  const from = (q.page - 1) * q.pageSize;
  const to = from + q.pageSize - 1;
  query = query.range(from, to);

  const { data: rows, count, error } = await query;
  if (error) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold">Usuarios</h1>
        <p className="text-sm text-destructive">
          Error al cargar la lista: {error.message}
        </p>
      </div>
    );
  }

  const total = count ?? 0;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Usuarios</h1>
        <p className="text-sm text-muted-foreground">
          {total} {total === 1 ? "usuario" : "usuarios"} en total.
        </p>
      </div>
      <FiltersBar query={q} />
      <UsersTable rows={rows ?? []} currentAdminRole={admin.role} />
      <Pagination query={q} total={total} />
    </div>
  );
}
```

- [ ] **Step 2: SKIP build verification**

Build will fail because `./filters-bar`, `./users-table`, and `./pagination` don't exist yet. Tasks 9–11 fix this; verification happens at the end of Task 11.

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/users/page.tsx"
git commit -m "feat(admin): /users list page shell (pending child components)"
```

---

## Task 9: `FiltersBar` client component

**Files:**
- Create: `admin/app/(dashboard)/users/filters-bar.tsx`

- [ ] **Step 1: Create the component**

Create `admin/app/(dashboard)/users/filters-bar.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/filters-bar.tsx
"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, useTransition } from "react";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  type RoleFilter,
  type StatusFilter,
  serializeUsersQuery,
  type UsersQuery,
} from "@/lib/users/search-params";

export function FiltersBar({ query }: { query: UsersQuery }) {
  const router = useRouter();
  const pathname = usePathname();
  const [, startTransition] = useTransition();
  const [search, setSearch] = useState(query.search);

  // Debounce the search input by 300ms before pushing to URL.
  useEffect(() => {
    if (search === query.search) return;
    const id = setTimeout(() => {
      startTransition(() => {
        router.push(
          pathname + serializeUsersQuery(query, { search, page: 1 }),
        );
      });
    }, 300);
    return () => clearTimeout(id);
  }, [search, query, router, pathname]);

  function pushOverride(o: Partial<UsersQuery>) {
    startTransition(() => {
      router.push(pathname + serializeUsersQuery(query, { ...o, page: 1 }));
    });
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Input
        placeholder="Buscar por email o apodo…"
        className="max-w-sm"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      <Select
        value={query.role}
        onValueChange={(v) => pushOverride({ role: v as RoleFilter })}
      >
        <SelectTrigger className="w-40">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todos los roles</SelectItem>
          <SelectItem value="user">user</SelectItem>
          <SelectItem value="admin">admin</SelectItem>
          <SelectItem value="superadmin">superadmin</SelectItem>
        </SelectContent>
      </Select>
      <Select
        value={query.status}
        onValueChange={(v) => pushOverride({ status: v as StatusFilter })}
      >
        <SelectTrigger className="w-36">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todos</SelectItem>
          <SelectItem value="active">Activos</SelectItem>
          <SelectItem value="banned">Baneados</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}
```

- [ ] **Step 2: SKIP build verification**

The page still references `./users-table` and `./pagination`. Wait for Task 11.

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/users/filters-bar.tsx"
git commit -m "feat(admin): /users filters bar"
```

---

## Task 10: `UsersTable` client component

**Files:**
- Create: `admin/app/(dashboard)/users/users-table.tsx`

- [ ] **Step 1: Create the table**

Create `admin/app/(dashboard)/users/users-table.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/users-table.tsx
"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type ColumnDef,
} from "@tanstack/react-table";
import { format } from "date-fns";
import { ArrowUpDown } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  parseUsersQuery,
  serializeUsersQuery,
  type SortKey,
} from "@/lib/users/search-params";

type Row = {
  id: string;
  nickname: string | null;
  avatar_url: string | null;
  role: string | null;
  email: string | null;
  signup_date: string | null;
  banned_until: string | null;
  last_activity: string | null;
  sessions_count: number | null;
  routes_count: number | null;
};

function fmt(date: string | null): string {
  if (!date) return "—";
  const d = new Date(date);
  if (Number.isNaN(d.getTime()) || d.getFullYear() < 2000) return "—";
  return format(d, "dd/MM/yyyy");
}

function statusOf(row: Row): "active" | "banned" {
  if (!row.banned_until) return "active";
  return new Date(row.banned_until) > new Date() ? "banned" : "active";
}

export function UsersTable({
  rows,
  currentAdminRole,
}: {
  rows: Row[];
  currentAdminRole: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseUsersQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: SortKey) {
    const dir =
      query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeUsersQuery(query, { sort: key, dir }));
  }

  function SortableHead({
    label,
    sortKey,
  }: {
    label: string;
    sortKey: SortKey;
  }) {
    const active = query.sort === sortKey;
    return (
      <Button
        variant="ghost"
        size="sm"
        className="-ml-3 h-7 px-2"
        onClick={() => toggleSort(sortKey)}
      >
        {label}
        <ArrowUpDown
          className={
            "ml-1 h-3 w-3 " +
            (active ? "text-foreground" : "text-muted-foreground")
          }
        />
      </Button>
    );
  }

  const columns: ColumnDef<Row>[] = [
    {
      id: "avatar",
      header: "",
      cell: ({ row }) => (
        <div className="h-8 w-8 overflow-hidden rounded-full bg-muted">
          {row.original.avatar_url ? (
            // Plain img to avoid Next.js image-host config for arbitrary URLs.
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.original.avatar_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "nickname",
      header: () => <SortableHead label="Nickname" sortKey="nickname" />,
      cell: ({ row }) => (
        <span className="font-medium">{row.original.nickname || "—"}</span>
      ),
    },
    {
      accessorKey: "email",
      header: "Email",
      cell: ({ row }) => row.original.email ?? "—",
    },
    {
      accessorKey: "role",
      header: "Rol",
      cell: ({ row }) => (
        <Badge
          variant={
            row.original.role === "superadmin"
              ? "default"
              : row.original.role === "admin"
                ? "secondary"
                : "outline"
          }
        >
          {row.original.role ?? "user"}
        </Badge>
      ),
    },
    {
      accessorKey: "signup_date",
      header: () => <SortableHead label="Alta" sortKey="signup_date" />,
      cell: ({ row }) => fmt(row.original.signup_date),
    },
    {
      accessorKey: "last_activity",
      header: () => (
        <SortableHead label="Última actividad" sortKey="last_activity" />
      ),
      cell: ({ row }) => fmt(row.original.last_activity),
    },
    {
      accessorKey: "sessions_count",
      header: () => <SortableHead label="Sesiones" sortKey="sessions_count" />,
      cell: ({ row }) => row.original.sessions_count ?? 0,
    },
    {
      accessorKey: "routes_count",
      header: () => <SortableHead label="Rutas" sortKey="routes_count" />,
      cell: ({ row }) => row.original.routes_count ?? 0,
    },
    {
      id: "status",
      header: "Estado",
      cell: ({ row }) => {
        const s = statusOf(row.original);
        return (
          <Badge variant={s === "banned" ? "destructive" : "outline"}>
            {s === "banned" ? "Baneado" : "Activo"}
          </Badge>
        );
      },
    },
  ];

  const table = useReactTable({
    data: rows,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  // Used in admin-only-features hints later if needed.
  void currentAdminRole;

  return (
    <div className="rounded-md border">
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((g) => (
            <TableRow key={g.id}>
              {g.headers.map((h) => (
                <TableHead key={h.id}>
                  {h.isPlaceholder
                    ? null
                    : flexRender(
                        h.column.columnDef.header,
                        h.getContext(),
                      )}
                </TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {table.getRowModel().rows.length === 0 ? (
            <TableRow>
              <TableCell
                colSpan={columns.length}
                className="text-center text-sm text-muted-foreground"
              >
                Sin resultados.
              </TableCell>
            </TableRow>
          ) : (
            table.getRowModel().rows.map((row) => (
              <TableRow
                key={row.id}
                className="cursor-pointer hover:bg-accent/40"
                onClick={() => router.push(`/users/${row.original.id}`)}
              >
                {row.getVisibleCells().map((cell) => (
                  <TableCell key={cell.id}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </TableCell>
                ))}
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </div>
  );
}
```

- [ ] **Step 2: SKIP build verification (Pagination still missing)**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/users/users-table.tsx"
git commit -m "feat(admin): /users TanStack table with sortable columns"
```

---

## Task 11: `Pagination` client component + build check

**Files:**
- Create: `admin/app/(dashboard)/users/pagination.tsx`

- [ ] **Step 1: Create the pager**

Create `admin/app/(dashboard)/users/pagination.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/pagination.tsx
"use client";

import { usePathname, useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  serializeUsersQuery,
  type UsersQuery,
} from "@/lib/users/search-params";

export function Pagination({
  query,
  total,
}: {
  query: UsersQuery;
  total: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const totalPages = Math.max(1, Math.ceil(total / query.pageSize));

  function go(page: number) {
    router.push(pathname + serializeUsersQuery(query, { page }));
  }

  return (
    <div className="flex items-center justify-between text-sm text-muted-foreground">
      <div>
        Página {query.page} de {totalPages}
      </div>
      <div className="flex items-center gap-2">
        <Select
          value={String(query.pageSize)}
          onValueChange={(v) =>
            router.push(
              pathname +
                serializeUsersQuery(query, {
                  pageSize: Number(v) as 25 | 50 | 100,
                  page: 1,
                }),
            )
          }
        >
          <SelectTrigger className="h-8 w-20">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="25">25</SelectItem>
            <SelectItem value="50">50</SelectItem>
            <SelectItem value="100">100</SelectItem>
          </SelectContent>
        </Select>
        <Button
          variant="outline"
          size="sm"
          disabled={query.page <= 1}
          onClick={() => go(query.page - 1)}
        >
          Anterior
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={query.page >= totalPages}
          onClick={() => go(query.page + 1)}
        >
          Siguiente
        </Button>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Run build end-to-end**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. All `/users` page imports resolve.

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/users/pagination.tsx"
git commit -m "feat(admin): /users pagination + page-size selector"
```

---

## Task 12: User detail page + tabs shell

**Files:**
- Create: `admin/app/(dashboard)/users/[id]/page.tsx`

This task creates the detail page shell with all five tabs wired but the tab CONTENT components (`profile-tab.tsx`, etc.) come in Tasks 13–17. Skip build verification until those land.

- [ ] **Step 1: Create the detail page**

Create `admin/app/(dashboard)/users/[id]/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/page.tsx
import { notFound } from "next/navigation";
import Link from "next/link";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import { ProfileTab } from "./profile-tab";
import { ActivityTab } from "./activity-tab";
import { GarageTab } from "./garage-tab";
import { RoutesTab } from "./routes-tab";
import { LogsTab } from "./logs-tab";
import { BanDialog } from "./ban-dialog";
import { ResetPasswordDialog } from "./reset-password-dialog";

export const dynamic = "force-dynamic";

export default async function UserDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const admin = await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("admin_users_view")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();

  const isBanned =
    !!row.banned_until && new Date(row.banned_until) > new Date();

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/users">← Volver a usuarios</Link>
      </Button>

      <div className="flex items-start gap-4">
        <div className="h-16 w-16 overflow-hidden rounded-full bg-muted">
          {row.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.avatar_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : null}
        </div>
        <div className="flex-1 space-y-1">
          <h1 className="text-2xl font-semibold">{row.nickname || "—"}</h1>
          <p className="text-sm text-muted-foreground">{row.email}</p>
          <div className="flex items-center gap-2">
            <Badge
              variant={
                row.role === "superadmin"
                  ? "default"
                  : row.role === "admin"
                    ? "secondary"
                    : "outline"
              }
            >
              {row.role ?? "user"}
            </Badge>
            <Badge variant={isBanned ? "destructive" : "outline"}>
              {isBanned ? "Baneado" : "Activo"}
            </Badge>
          </div>
        </div>
      </div>

      <Tabs defaultValue="profile" className="space-y-4">
        <TabsList>
          <TabsTrigger value="profile">Perfil</TabsTrigger>
          <TabsTrigger value="activity">Actividad</TabsTrigger>
          <TabsTrigger value="garage">Garaje</TabsTrigger>
          <TabsTrigger value="routes">Rutas</TabsTrigger>
          <TabsTrigger value="logs">Logs</TabsTrigger>
        </TabsList>

        <TabsContent value="profile">
          <ProfileTab
            userId={row.id!}
            initialNickname={row.nickname ?? ""}
            currentRole={row.role ?? "user"}
            actorRole={admin.role}
          />
        </TabsContent>
        <TabsContent value="activity">
          <ActivityTab userId={row.id!} />
        </TabsContent>
        <TabsContent value="garage">
          <GarageTab userId={row.id!} />
        </TabsContent>
        <TabsContent value="routes">
          <RoutesTab userId={row.id!} />
        </TabsContent>
        <TabsContent value="logs">
          <LogsTab userId={row.id!} />
        </TabsContent>
      </Tabs>

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <div className="flex flex-wrap gap-2">
          <BanDialog
            userId={row.id!}
            userEmail={row.email ?? ""}
            isBanned={isBanned}
            bannedUntil={row.banned_until}
          />
          <ResetPasswordDialog
            userId={row.id!}
            userEmail={row.email ?? ""}
          />
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: SKIP build verification**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/users/[id]/page.tsx"
git commit -m "feat(admin): /users/[id] detail page shell"
```

---

## Task 13: Server Actions for user detail

**Files:**
- Create: `admin/app/(dashboard)/users/[id]/actions.ts`

- [ ] **Step 1: Create the actions module**

Create `admin/app/(dashboard)/users/[id]/actions.ts` with EXACTLY:

```ts
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
```

- [ ] **Step 2: SKIP build verification (tabs still pending)**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/users/[id]/actions.ts"
git commit -m "feat(admin): user detail server actions (edit, ban, unban, reset)"
```

---

## Task 14: Profile tab + Ban dialog + Reset-password dialog

**Files:**
- Create: `admin/app/(dashboard)/users/[id]/profile-tab.tsx`
- Create: `admin/app/(dashboard)/users/[id]/ban-dialog.tsx`
- Create: `admin/app/(dashboard)/users/[id]/reset-password-dialog.tsx`

- [ ] **Step 1: Profile tab (client)**

Create `admin/app/(dashboard)/users/[id]/profile-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/profile-tab.tsx
"use client";

import { useActionState, useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { editUserProfile, type EditProfileState } from "./actions";

const initialState: EditProfileState = {};

export function ProfileTab({
  userId,
  initialNickname,
  currentRole,
  actorRole,
}: {
  userId: string;
  initialNickname: string;
  currentRole: string;
  actorRole: "admin" | "superadmin";
}) {
  const [state, formAction, isPending] = useActionState(
    editUserProfile,
    initialState,
  );
  const [bio, setBio] = useState<string>("");

  useEffect(() => {
    if (state.ok) toast.success("Perfil actualizado.");
  }, [state]);

  const isSuperadmin = actorRole === "superadmin";

  return (
    <Card>
      <CardHeader>
        <CardTitle>Perfil</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4">
          <input type="hidden" name="userId" value={userId} />
          <div className="space-y-2">
            <Label htmlFor="nickname">Apodo</Label>
            <Input
              id="nickname"
              name="nickname"
              defaultValue={initialNickname}
              minLength={2}
              maxLength={24}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="bio">Bio</Label>
            <textarea
              id="bio"
              name="bio"
              value={bio}
              onChange={(e) => setBio(e.target.value)}
              maxLength={500}
              className="flex min-h-[80px] w-full rounded-md border bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
          <div className="space-y-2">
            <Label>Rol</Label>
            {isSuperadmin ? (
              <p className="text-sm text-muted-foreground">
                Para cambiar el rol usa <strong>Configuración →
                Administradores</strong>. (Rol actual:{" "}
                <span className="font-medium">{currentRole}</span>.)
              </p>
            ) : (
              <p className="text-sm text-muted-foreground">
                Rol actual: <span className="font-medium">{currentRole}</span>.
                Solo los superadmins pueden cambiar roles.
              </p>
            )}
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

- [ ] **Step 2: Ban dialog (client)**

Create `admin/app/(dashboard)/users/[id]/ban-dialog.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/ban-dialog.tsx
"use client";

import { useActionState, useEffect, useState } from "react";
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { banUser, unbanUser, type BanState } from "./actions";

const initialState: BanState = {};

// 100 years × 365 days × 24 hours ≈ practical "permanent".
const PERMANENT_HOURS = 100 * 365 * 24;

const DURATIONS: { label: string; hours: number }[] = [
  { label: "1 hora", hours: 1 },
  { label: "24 horas", hours: 24 },
  { label: "7 días", hours: 24 * 7 },
  { label: "30 días", hours: 24 * 30 },
  { label: "Permanente", hours: PERMANENT_HOURS },
];

export function BanDialog({
  userId,
  userEmail,
  isBanned,
  bannedUntil,
}: {
  userId: string;
  userEmail: string;
  isBanned: boolean;
  bannedUntil: string | null;
}) {
  if (isBanned) {
    return (
      <UnbanButton userId={userId} userEmail={userEmail} until={bannedUntil} />
    );
  }
  return <BanButton userId={userId} userEmail={userEmail} />;
}

function BanButton({
  userId,
  userEmail,
}: {
  userId: string;
  userEmail: string;
}) {
  const [state, formAction, isPending] = useActionState(banUser, initialState);
  const [hours, setHours] = useState<string>("24");

  useEffect(() => {
    if (state.ok) toast.success("Usuario baneado.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Banear</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Banear a {userEmail}</AlertDialogTitle>
          <AlertDialogDescription>
            Mientras dure el ban el usuario no podrá iniciar sesión. Esta
            acción queda registrada en el audit log.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction} className="space-y-3">
          <input type="hidden" name="userId" value={userId} />
          <input type="hidden" name="durationHours" value={hours} />
          <Select value={hours} onValueChange={setHours}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {DURATIONS.map((d) => (
                <SelectItem key={d.hours} value={String(d.hours)}>
                  {d.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Aplicando…" : "Banear"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function UnbanButton({
  userId,
  userEmail,
  until,
}: {
  userId: string;
  userEmail: string;
  until: string | null;
}) {
  const [state, formAction, isPending] = useActionState(
    unbanUser,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Ban levantado.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline">
          Quitar ban{until ? ` (hasta ${new Date(until).toLocaleDateString()})` : ""}
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Levantar ban de {userEmail}</AlertDialogTitle>
          <AlertDialogDescription>
            El usuario podrá iniciar sesión de nuevo inmediatamente.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="userId" value={userId} />
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Quitando…" : "Quitar ban"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}
```

- [ ] **Step 3: Reset-password dialog (client)**

Create `admin/app/(dashboard)/users/[id]/reset-password-dialog.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/reset-password-dialog.tsx
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
import { resetUserPassword, type ResetState } from "./actions";

const initialState: ResetState = {};

export function ResetPasswordDialog({
  userId,
  userEmail,
}: {
  userId: string;
  userEmail: string;
}) {
  const [state, formAction, isPending] = useActionState(
    resetUserPassword,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Email de reseteo enviado.");
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="outline">Resetear contraseña</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Resetear contraseña</AlertDialogTitle>
          <AlertDialogDescription>
            Se enviará un email a <strong>{userEmail}</strong> con un enlace
            para fijar una nueva contraseña.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="userId" value={userId} />
          <input type="hidden" name="email" value={userEmail} />
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Enviando…" : "Enviar"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}
```

- [ ] **Step 4: SKIP build verification (Activity/Garage/Routes/Logs tabs still pending)**

- [ ] **Step 5: Commit**

```powershell
git add "admin/app/(dashboard)/users/[id]/profile-tab.tsx" "admin/app/(dashboard)/users/[id]/ban-dialog.tsx" "admin/app/(dashboard)/users/[id]/reset-password-dialog.tsx"
git commit -m "feat(admin): user detail profile tab + ban + reset dialogs"
```

---

## Task 15: Activity, Garage, Routes tabs

**Files:**
- Create: `admin/app/(dashboard)/users/[id]/activity-tab.tsx`
- Create: `admin/app/(dashboard)/users/[id]/garage-tab.tsx`
- Create: `admin/app/(dashboard)/users/[id]/routes-tab.tsx`

- [ ] **Step 1: Activity tab (server component)**

Create `admin/app/(dashboard)/users/[id]/activity-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/activity-tab.tsx
import { format } from "date-fns";
import { adminClient } from "@/lib/supabase/admin";
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

type Activity = {
  kind: "session_run" | "free_ride" | "speed_session";
  id: string;
  created_at: string;
  label: string;
};

export async function ActivityTab({ userId }: { userId: string }) {
  const supabase = adminClient();

  const [runs, rides, speeds] = await Promise.all([
    supabase
      .from("session_runs")
      .select("id, started_at, status")
      .eq("owner_id", userId)
      .order("started_at", { ascending: false })
      .limit(50),
    supabase
      .from("free_rides")
      .select("id, started_at, name, location_label")
      .eq("owner_id", userId)
      .order("started_at", { ascending: false })
      .limit(50),
    supabase
      .from("speed_sessions")
      .select("id, started_at, name")
      .eq("user_id", userId)
      .order("started_at", { ascending: false })
      .limit(50),
  ]);

  const all: Activity[] = [
    ...(runs.data ?? []).map((r) => ({
      kind: "session_run" as const,
      id: r.id,
      created_at: r.started_at,
      label: `Sesión cronometrada (${r.status})`,
    })),
    ...(rides.data ?? []).map((r) => ({
      kind: "free_ride" as const,
      id: r.id,
      created_at: r.started_at,
      label: r.name || r.location_label || "Salida libre",
    })),
    ...(speeds.data ?? []).map((s) => ({
      kind: "speed_session" as const,
      id: s.id,
      created_at: s.started_at,
      label: s.name || "Drag strip",
    })),
  ]
    .sort((a, b) => b.created_at.localeCompare(a.created_at))
    .slice(0, 100);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Actividad reciente</CardTitle>
      </CardHeader>
      <CardContent>
        {all.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sin actividad.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tipo</TableHead>
                <TableHead>Descripción</TableHead>
                <TableHead className="w-32">Cuando</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {all.map((a) => (
                <TableRow key={`${a.kind}:${a.id}`}>
                  <TableCell>
                    <Badge variant="outline">{a.kind}</Badge>
                  </TableCell>
                  <TableCell>{a.label}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(a.created_at), "dd/MM/yyyy HH:mm")}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Garage tab (server component)**

Create `admin/app/(dashboard)/users/[id]/garage-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/garage-tab.tsx
import { adminClient } from "@/lib/supabase/admin";
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

export async function GarageTab({ userId }: { userId: string }) {
  const supabase = adminClient();
  const { data: vehicles } = await supabase
    .from("vehicles")
    .select("id, name, type, model, year, horsepower")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Garaje</CardTitle>
      </CardHeader>
      <CardContent>
        {!vehicles || vehicles.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Este usuario no tiene vehículos.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nombre</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Modelo</TableHead>
                <TableHead>Año</TableHead>
                <TableHead>CV</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {vehicles.map((v) => (
                <TableRow key={v.id}>
                  <TableCell className="font-medium">{v.name}</TableCell>
                  <TableCell>
                    <Badge variant="outline">{v.type}</Badge>
                  </TableCell>
                  <TableCell>{v.model ?? "—"}</TableCell>
                  <TableCell>{v.year ?? "—"}</TableCell>
                  <TableCell>{v.horsepower ?? "—"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 3: Routes tab (server component)**

Create `admin/app/(dashboard)/users/[id]/routes-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/routes-tab.tsx
import { format } from "date-fns";
import { adminClient } from "@/lib/supabase/admin";
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

export async function RoutesTab({ userId }: { userId: string }) {
  const supabase = adminClient();
  const { data: routes } = await supabase
    .from("route_templates")
    .select("id, name, difficulty, location_label, created_at")
    .eq("owner_id", userId)
    .order("created_at", { ascending: false });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Rutas creadas</CardTitle>
      </CardHeader>
      <CardContent>
        {!routes || routes.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Este usuario no ha creado rutas.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nombre</TableHead>
                <TableHead>Dificultad</TableHead>
                <TableHead>Ubicación</TableHead>
                <TableHead className="w-32">Creada</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {routes.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-medium">{r.name}</TableCell>
                  <TableCell>
                    <Badge variant="outline">{r.difficulty}</Badge>
                  </TableCell>
                  <TableCell>{r.location_label ?? "—"}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(r.created_at), "dd/MM/yyyy")}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 4: SKIP build verification (Logs tab still pending)**

- [ ] **Step 5: Commit**

```powershell
git add "admin/app/(dashboard)/users/[id]/activity-tab.tsx" "admin/app/(dashboard)/users/[id]/garage-tab.tsx" "admin/app/(dashboard)/users/[id]/routes-tab.tsx"
git commit -m "feat(admin): user detail activity, garage, routes tabs"
```

---

## Task 16: Logs tab + final build

**Files:**
- Create: `admin/app/(dashboard)/users/[id]/logs-tab.tsx`

- [ ] **Step 1: Logs tab (server component)**

Create `admin/app/(dashboard)/users/[id]/logs-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/users/[id]/logs-tab.tsx
import { format } from "date-fns";
import { adminClient } from "@/lib/supabase/admin";
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

const LEVEL_COLOR: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  debug: "outline",
  info: "secondary",
  warning: "default",
  error: "destructive",
};

export async function LogsTab({ userId }: { userId: string }) {
  const supabase = adminClient();
  const { data: logs } = await supabase
    .from("app_logs")
    .select("id, timestamp, level, tag, message, app_version, platform")
    .eq("user_id", userId)
    .order("timestamp", { ascending: false })
    .limit(100);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Logs recientes</CardTitle>
      </CardHeader>
      <CardContent>
        {!logs || logs.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Este usuario no tiene logs (el viewer completo llega en F6).
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-32">Cuando</TableHead>
                <TableHead className="w-20">Nivel</TableHead>
                <TableHead className="w-28">Tag</TableHead>
                <TableHead>Mensaje</TableHead>
                <TableHead className="w-24">Versión</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {logs.map((l) => (
                <TableRow key={l.id}>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(l.timestamp), "dd/MM HH:mm:ss")}
                  </TableCell>
                  <TableCell>
                    <Badge variant={LEVEL_COLOR[l.level] ?? "outline"}>
                      {l.level}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {l.tag}
                  </TableCell>
                  <TableCell className="text-sm">{l.message}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {l.app_version} ({l.platform})
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Run full build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. All routes compile, types pass.

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/users/[id]/logs-tab.tsx"
git commit -m "feat(admin): user detail logs tab (read-only, F6 will expand)"
```

---

## Task 17: Manual end-to-end verification

**Files:** none — verification only.

- [ ] **Step 1: Start the panel**

```powershell
cd admin
docker compose up     # or pnpm dev
```

- [ ] **Step 2: List page (criteria 1–6)**

1. Sign in as superadmin. Click **Usuarios** in the sidebar.
2. Confirm: header shows total count; 9 columns; first page of rows renders; row click sends you to the detail page.
3. Type in the search box → after 300ms, table refetches and shows only matching rows. URL gains `?search=…`.
4. Change role filter to `admin` → table filters down. URL gains `&role=admin`.
5. Change status filter to `Baneados` → table empty (probably). URL `&status=banned`.
6. Click the **Alta** column header → table reorders ascending. Click again → descending. URL toggles `&sort=signup_date&dir=…`.
7. Click **Siguiente** in the pager → page=2 if there are enough rows. Change pageSize to 50 → URL `&pageSize=50&page=1`.

- [ ] **Step 3: Detail page header + tabs (criteria 7–8)**

1. Click any row to open `/users/[id]`.
2. Header shows avatar (or empty circle), nickname, email, role badge, status badge.
3. Open each tab in order: Perfil (form), Actividad (table or "Sin actividad"), Garaje, Rutas, Logs. Each renders without error.

- [ ] **Step 4: Edit profile (criterion 9)**

1. In Perfil, change the nickname and click Guardar.
2. Success toast appears. Reload the page → new nickname persists. Header reflects it.
3. SQL check:
   ```sql
   select action, target_id, details, created_at
   from public.admin_audit_log
   where action = 'edit_user_profile'
   order by created_at desc limit 1;
   ```
   Confirm details has actorEmail, before, after.

- [ ] **Step 5: Ban + Unban (criteria 10–11)**

1. Click **Banear**, pick "1 hora", confirm.
2. Toast "Usuario baneado". Status badge flips to **Baneado**. The Ban button becomes **Quitar ban (hasta …)**.
3. Audit log: `ban_user` with `durationHours: 1`.
4. Sign out and try to sign in as the banned user → Supabase rejects with the standard "Invalid login credentials" or banned message. (Optional check.)
5. Back in the panel, click **Quitar ban**, confirm. Toast "Ban levantado". Status returns to **Activo**.
6. Audit log: `unban_user`.

- [ ] **Step 6: Reset password (criterion 12)**

1. Click **Resetear contraseña**, confirm.
2. Toast "Email de reseteo enviado". The user receives a Supabase password-reset email.
3. Audit log: `reset_user_password` with `targetEmail`.

- [ ] **Step 7: Role visibility (criterion 13)**

1. Sign in as a plain `admin` (not superadmin). Open `/users/[id]/`.
2. Perfil tab: confirm the role section says "Solo los superadmins pueden cambiar roles" (no controls).
3. Other actions work as expected.

- [ ] **Step 8: Done**

If all 13 acceptance criteria pass → F3 is complete. Hand off to `superpowers:finishing-a-development-branch`.

---

## Notes for the executor

- **No tests in this phase.** Per spec §9 — only pure helpers + critical E2E (deferred to F8) get automated tests.
- **`auth.admin.updateUserById({ ban_duration })`** accepts strings like `"24h"`, `"none"`. We always pass an hours suffix; "permanent" is just a very large number of hours.
- **`generateLink({ type: "recovery" })`** sends the email AND returns the link. We discard the link; the user clicks the one in their inbox. If Supabase SMTP isn't configured for the project, emails may go to the spam folder or fail — that's a config issue, not a code one.
- **Server-side pagination** is implemented via `.range(from, to)` + `{ count: "exact" }`. For very large user bases (>10k) the exact count becomes slow; revisit with `{ count: "estimated" }` if needed.
- **The search filter uses `.ilike`** which is case-insensitive. For more complex matching (multiple terms, prefix), revisit with full-text search later.
- **The view's `routes_count`** counts every `route_templates` row owned by the user, including ones the admin marks `is_official` in F4. That's intentional — admin moderation doesn't affect ownership.
- **Tab content is rendered server-side per request** — there's no client-side state for tab data. If a tab gets heavy (e.g. Activity with thousands of rows), revisit with infinite scroll or lazy loading.
- **The Profile tab's role section is read-only** in this phase — the role change UI lives in `/settings → Administradores` to keep the auditable promote/demote flow in one place.
