# Admin Panel — Phase F4 (Routes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/routes` admin surface — a paginated, filterable list of every `route_templates` row, and a `/routes/[id]` detail page with a Mapbox map, sector list, sessions list, editable metadata, an `is_official` toggle, plus duplicate-as-official and delete actions.

**Architecture:** Mirrors F3 (Users) — one SQL view (`admin_routes_view`) joins routes with their owner's nickname/email plus per-route sectors/sessions counts, TanStack Table v8 drives the list with URL-state pagination/sort/filters, Server Components fetch all data, and Server Actions perform mutations through the existing `adminClient` (service_role). One new Postgres function (`duplicate_route_as_official`) keeps the clone-and-set-flag operation atomic across `route_templates` and `sectors`. Mapbox GL JS is added on the client only, behind a dynamic import so it's not bundled into pages that don't need it.

**Tech Stack:** Inherited from F3 — Next.js 16, `@supabase/ssr`, Zod, shadcn/ui, sonner, TanStack Table v8, date-fns. **New:** `mapbox-gl@^3` for the route preview. **New env var:** `NEXT_PUBLIC_MAPBOX_TOKEN` (consumed by the client map; obtainable from <https://account.mapbox.com/>).

**Branch:** `feat/admin-routes` (already created from `main` after F3 merged via PR #13).

**Out of scope for F4 (handled later):**
- Editing the route's geometry (path, sectors). The map is read-only. Path edits stay in the Flutter app.
- Bulk operations on routes.
- Surfacing `is_official` in the Flutter app — that's a follow-up Flutter PR (spec §6.3).
- Performance work for large route lists (>10k). Revisit when needed.
- Thumbnail regeneration. We display `route_templates.thumbnail_url` as-is; if it's null we show a placeholder.

**Acceptance criteria (verified at Task 17, in the browser):**
1. The sidebar gains a **Rutas** entry. Clicking it loads `/routes` in under a second.
2. The list shows columns: thumbnail (or placeholder), name, owner nickname, difficulty badge, sectors count, sessions count, location, created date.
3. Pagination works: default 25 rows, switching pages preserves filters + sort via the URL.
4. Free-text search filters by route name OR owner nickname OR location_label; debounced 300ms.
5. Filtering by `difficulty` (easy/medium/hard/extreme) narrows the list correctly.
6. Sorting by name, difficulty, sectors count, sessions count, and created date works in both directions.
7. Clicking a row navigates to `/routes/[id]` and shows the route name, difficulty badge, official badge if applicable, owner info, sectors count, sessions count at the top.
8. The map renders the route polyline. The bounds fit the polyline. The map is non-interactive for path editing (drag/zoom/rotate is fine).
9. The metadata form lets the admin edit name, description, difficulty (select), location_label. Saving updates the row, writes an `edit_route` audit entry, and shows a success toast.
10. The "Marcar como oficial" toggle flips `is_official`. The audit log records `mark_route_official` or `unmark_route_official` accordingly. The badge updates.
11. The "Duplicar como oficial" action creates a new row with the same path + sectors, `is_official = true`, `owner_id = currentAdmin.id`, name `Oficial — <original name>`. Writes a `duplicate_route` audit entry. Redirects to the new route's detail page with a toast.
12. The "Eliminar" action deletes the route (cascade deletes sectors and orphans session_runs via existing FKs), writes a `delete_route` audit entry, and redirects to the list with a toast.
13. A plain `admin` (not superadmin) has the same access as a superadmin for everything in F4 — there is no superadmin-only operation on routes.

---

## File Structure

**New files:**

```
admin/
├── app/(dashboard)/routes/
│   ├── page.tsx                              # list page (Server Component)
│   ├── routes-table.tsx                      # client TanStack Table
│   ├── filters-bar.tsx                       # client filters (search + difficulty)
│   ├── pagination.tsx                        # client pager (Prev/Next + page size)
│   └── [id]/
│       ├── page.tsx                          # detail Server Component
│       ├── actions.ts                        # editRoute + toggleOfficial + duplicate + delete
│       ├── route-map.tsx                     # client Mapbox component
│       ├── metadata-form.tsx                 # client edit form
│       ├── sectors-card.tsx                  # server component
│       ├── sessions-card.tsx                 # server component
│       ├── official-toggle.tsx               # client switch with confirm
│       └── delete-dialog.tsx                 # client confirm dialog
├── lib/routes/
│   └── search-params.ts                      # parse + serialize ?page=&sort=&search=...
supabase/migrations/
├── 20260601000000_route_templates_is_official.sql        # add column + index
├── 20260601000001_admin_routes_view.sql                  # joined view + grant
└── 20260601000002_duplicate_route_as_official.sql        # atomic clone RPC
```

**Modified files:**

- `admin/components/shared/sidebar.tsx` — add `/routes` link with the `Map` lucide icon.
- `admin/lib/audit.ts` — extend `AuditAction` union with `edit_route`, `mark_route_official`, `unmark_route_official`, `duplicate_route`. `delete_route` is already reserved.
- `admin/lib/supabase/database.types.ts` — regenerated to include the new view + function + column.
- `admin/.env.local.example` — document `NEXT_PUBLIC_MAPBOX_TOKEN`.
- `admin/package.json` + `admin/pnpm-lock.yaml` — add `mapbox-gl` + `@types/mapbox-gl`.

---

## Task 1: Migration — `route_templates.is_official` column

**Files:**
- Create: `supabase/migrations/20260601000000_route_templates_is_official.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260601000000_route_templates_is_official.sql` with EXACTLY:

```sql
-- supabase/migrations/20260601000000_route_templates_is_official.sql
-- Mark a route as "official" — curated by the admin team and visible
-- to every Flutter user (the visibility wiring is a separate follow-up
-- Flutter PR, this migration is only the schema change).

alter table public.route_templates
  add column if not exists is_official boolean not null default false;

-- Partial index: official routes are the minority, so a partial index
-- keeps the bulk of the table out of the index entirely.
create index if not exists route_templates_is_official_idx
  on public.route_templates (is_official)
  where is_official = true;
```

- [ ] **Step 2: Apply to cloud**

```powershell
supabase db push
```

Expected: applies the migration, exits 0.

- [ ] **Step 3: Verify**

In the Supabase Dashboard SQL editor:
```sql
select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'route_templates'
  and column_name = 'is_official';
```

Confirm one row with `data_type = 'boolean'` and `column_default = 'false'`.

- [ ] **Step 4: Commit**

```powershell
git add supabase/migrations/20260601000000_route_templates_is_official.sql
git commit -m "feat(db): route_templates.is_official column with partial index"
```

---

## Task 2: Migration — `admin_routes_view`

**Files:**
- Create: `supabase/migrations/20260601000001_admin_routes_view.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260601000001_admin_routes_view.sql` with EXACTLY:

```sql
-- supabase/migrations/20260601000001_admin_routes_view.sql
-- Single-query feed for the admin panel's /routes list. Joins route
-- metadata with the owner's nickname and email, and per-route counts
-- for sectors and sessions. Service-role only.

create or replace view public.admin_routes_view as
select
  r.id,
  r.name,
  r.description,
  r.difficulty,
  r.location_label,
  r.thumbnail_url,
  r.is_official,
  r.created_at,
  r.owner_id,
  p.nickname as owner_nickname,
  u.email as owner_email,
  coalesce(
    (select count(*) from public.sectors where route_id = r.id),
    0
  ) as sectors_count,
  coalesce(
    (select count(*) from public.session_runs where route_id = r.id),
    0
  ) as sessions_count
from public.route_templates r
left join public.profiles p on p.id = r.owner_id
left join auth.users u on u.id = r.owner_id;

revoke all on public.admin_routes_view from public, anon, authenticated;
grant select on public.admin_routes_view to service_role;
```

- [ ] **Step 2: Apply**

```powershell
supabase db push
```

- [ ] **Step 3: Verify**

In the Supabase Dashboard SQL editor:
```sql
select id, name, owner_nickname, difficulty, sectors_count, sessions_count, is_official
from public.admin_routes_view
order by created_at desc
limit 5;
```

Confirm rows return with all 13 columns populated.

- [ ] **Step 4: Commit**

```powershell
git add supabase/migrations/20260601000001_admin_routes_view.sql
git commit -m "feat(db): admin_routes_view joining owner + counts"
```

---

## Task 3: Migration — `duplicate_route_as_official` RPC

**Files:**
- Create: `supabase/migrations/20260601000002_duplicate_route_as_official.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260601000002_duplicate_route_as_official.sql` with EXACTLY:

```sql
-- supabase/migrations/20260601000002_duplicate_route_as_official.sql
-- Atomic clone of a route + its sectors into a new route_templates row
-- marked is_official = true, owned by the admin who triggered the
-- duplication. Returns the new route's id. SECURITY DEFINER + a
-- service-role grant keeps it usable only from Server Actions.

create or replace function public.duplicate_route_as_official(
  p_source_route_id uuid,
  p_admin_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid := gen_random_uuid();
  v_source record;
begin
  select * into v_source
  from public.route_templates
  where id = p_source_route_id;
  if not found then
    raise exception 'Source route % not found', p_source_route_id
      using errcode = 'P0002';
  end if;

  insert into public.route_templates (
    id, name, description, difficulty, elevation_range_m,
    location_label, owner_id, path_json, start_finish_gate_json,
    thumbnail_url, is_official, created_at, updated_at
  ) values (
    v_new_id,
    'Oficial — ' || v_source.name,
    v_source.description,
    v_source.difficulty,
    v_source.elevation_range_m,
    v_source.location_label,
    p_admin_id,
    v_source.path_json,
    v_source.start_finish_gate_json,
    v_source.thumbnail_url,
    true,
    now(),
    now()
  );

  insert into public.sectors (id, route_id, label, order_index, gate_json)
  select gen_random_uuid(), v_new_id, label, order_index, gate_json
  from public.sectors
  where route_id = p_source_route_id;

  return v_new_id;
end;
$$;

revoke execute on function
  public.duplicate_route_as_official(uuid, uuid) from public;
revoke execute on function
  public.duplicate_route_as_official(uuid, uuid) from anon;
revoke execute on function
  public.duplicate_route_as_official(uuid, uuid) from authenticated;
grant execute on function
  public.duplicate_route_as_official(uuid, uuid) to service_role;
```

- [ ] **Step 2: Apply**

```powershell
supabase db push
```

- [ ] **Step 3: Smoke-test (optional)**

If you have a test route already, you can run a dry-run against the cloud:
```sql
-- replace UUIDs with real ones
select public.duplicate_route_as_official(
  '<some-route-id>'::uuid,
  '<your-admin-id>'::uuid
);
```
Confirm a new row appears in `route_templates` with `is_official = true` and the same sectors are cloned. Delete the test row afterwards.

- [ ] **Step 4: Commit**

```powershell
git add supabase/migrations/20260601000002_duplicate_route_as_official.sql
git commit -m "feat(db): duplicate_route_as_official RPC"
```

---

## Task 4: Regenerate `database.types.ts`

**Files:**
- Modify (regenerate): `admin/lib/supabase/database.types.ts`

- [ ] **Step 1: Regenerate**

```powershell
supabase gen types typescript --linked --schema public 2>$null > admin/lib/supabase/database.types.ts
```

Open the file and confirm:
- `route_templates.Row` now has `is_official: boolean`.
- `admin_routes_view` appears under `public.Views` with the 13 columns.
- `duplicate_route_as_official` appears under `public.Functions` with `Args: { p_source_route_id: string; p_admin_id: string }; Returns: string`.

- [ ] **Step 2: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 3: Commit**

```powershell
git add admin/lib/supabase/database.types.ts
git commit -m "chore(admin): regenerate types for is_official + admin_routes_view + RPC"
```

---

## Task 5: Install Mapbox GL JS + env doc

**Files:**
- Modify: `admin/package.json`
- Modify: `admin/pnpm-lock.yaml`
- Modify: `admin/.env.local.example`

- [ ] **Step 1: Install**

```powershell
cd admin
pnpm add mapbox-gl
pnpm add -D @types/mapbox-gl
cd ..
```

Expected: both packages added.

- [ ] **Step 2: Document the env var**

Open `admin/.env.local.example`. AFTER the existing `SUPABASE_SERVICE_ROLE_KEY=` line, append:

```env

# Public — safe in the browser. Used by the /routes/[id] map preview.
# Get a token from https://account.mapbox.com/ → "Default public token"
# or create a new one scoped to "styles:read" + "fonts:read" + "tiles:read".
NEXT_PUBLIC_MAPBOX_TOKEN=
```

- [ ] **Step 3: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. (Mapbox isn't imported anywhere yet, so this only verifies install.)

- [ ] **Step 4: Commit**

```powershell
git add admin/package.json admin/pnpm-lock.yaml admin/.env.local.example
git commit -m "feat(admin): add mapbox-gl and NEXT_PUBLIC_MAPBOX_TOKEN"
```

---

## Task 6: Extend `AuditAction` union for F4 actions

**Files:**
- Modify: `admin/lib/audit.ts`

- [ ] **Step 1: Update the union**

Open `admin/lib/audit.ts`. The current `AuditAction` union has F2/F3 entries and a "Reserved for later phases" block that includes `edit_route`, `mark_route_official`, `delete_route`. Move those into a new F4 block, add `unmark_route_official` and `duplicate_route`. The final union should read:

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
  // F4 actions:
  | "edit_route"
  | "mark_route_official"
  | "unmark_route_official"
  | "duplicate_route"
  | "delete_route"
  // Reserved for later phases (kept here so the union is stable):
  | "delete_user"
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
git commit -m "feat(admin): F4 audit actions in union"
```

---

## Task 7: Sidebar entry for `/routes`

**Files:**
- Modify: `admin/components/shared/sidebar.tsx`

- [ ] **Step 1: Add the entry**

Open `admin/components/shared/sidebar.tsx`. It currently imports `{ Home, Settings, Users }` from `lucide-react`. Change to `{ Home, Map, Settings, Users }` and add a `/routes` entry between Usuarios and Configuración:

```tsx
import { Home, Map, Settings, Users } from "lucide-react";

const NAV_ITEMS = [
  { href: "/", label: "Inicio", icon: Home },
  { href: "/users", label: "Usuarios", icon: Users },
  { href: "/routes", label: "Rutas", icon: Map },
  { href: "/settings", label: "Configuración", icon: Settings },
] as const;
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
git add admin/components/shared/sidebar.tsx
git commit -m "feat(admin): sidebar entry for /routes"
```

---

## Task 8: URL search-params helper

**Files:**
- Create: `admin/lib/routes/search-params.ts`

- [ ] **Step 1: Create the helper**

Create `admin/lib/routes/search-params.ts` with EXACTLY:

```ts
// admin/lib/routes/search-params.ts
// Mirrors admin/lib/users/search-params.ts. No `import "server-only"`
// because the filter/pager client components also consume it.

export type DifficultyFilter = "all" | "easy" | "medium" | "hard" | "extreme";
export type OfficialFilter = "all" | "official" | "community";
export type SortKey =
  | "created_at"
  | "name"
  | "difficulty"
  | "sectors_count"
  | "sessions_count";
export type SortDir = "asc" | "desc";

export type RoutesQuery = {
  page: number;
  pageSize: number;
  search: string;
  difficulty: DifficultyFilter;
  official: OfficialFilter;
  sort: SortKey;
  dir: SortDir;
};

const DEFAULTS: RoutesQuery = {
  page: 1,
  pageSize: 25,
  search: "",
  difficulty: "all",
  official: "all",
  sort: "created_at",
  dir: "desc",
};

const DIFFICULTIES: readonly DifficultyFilter[] = [
  "all",
  "easy",
  "medium",
  "hard",
  "extreme",
];
const OFFICIALS: readonly OfficialFilter[] = ["all", "official", "community"];
const SORTS: readonly SortKey[] = [
  "created_at",
  "name",
  "difficulty",
  "sectors_count",
  "sessions_count",
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

export function parseRoutesQuery(
  searchParams: Record<string, string | string[] | undefined>,
): RoutesQuery {
  const raw = (key: string): string | undefined => {
    const v = searchParams[key];
    return Array.isArray(v) ? v[0] : v;
  };
  const pageRaw = Number.parseInt(raw("page") ?? "", 10);
  const pageSizeRaw = Number.parseInt(raw("pageSize") ?? "", 10);
  return {
    page: Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : DEFAULTS.page,
    pageSize: [25, 50, 100].includes(pageSizeRaw)
      ? pageSizeRaw
      : DEFAULTS.pageSize,
    search: (raw("search") ?? DEFAULTS.search)
      .replace(/[,:]/g, " ")
      .slice(0, 100),
    difficulty: pickOne(raw("difficulty"), DIFFICULTIES, DEFAULTS.difficulty),
    official: pickOne(raw("official"), OFFICIALS, DEFAULTS.official),
    sort: pickOne(raw("sort"), SORTS, DEFAULTS.sort),
    dir: pickOne(raw("dir"), DIRS, DEFAULTS.dir),
  };
}

export function serializeRoutesQuery(
  current: RoutesQuery,
  override: Partial<RoutesQuery>,
): string {
  const merged: RoutesQuery = { ...current, ...override };
  const params = new URLSearchParams();
  if (merged.page !== DEFAULTS.page) params.set("page", String(merged.page));
  if (merged.pageSize !== DEFAULTS.pageSize) {
    params.set("pageSize", String(merged.pageSize));
  }
  if (merged.search !== DEFAULTS.search) params.set("search", merged.search);
  if (merged.difficulty !== DEFAULTS.difficulty) {
    params.set("difficulty", merged.difficulty);
  }
  if (merged.official !== DEFAULTS.official) {
    params.set("official", merged.official);
  }
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
git add admin/lib/routes/search-params.ts
git commit -m "feat(admin): URL search-params parser for /routes"
```

---

## Task 9: `/routes` list page shell

**Files:**
- Create: `admin/app/(dashboard)/routes/page.tsx`

This task creates the Server Component shell. It references `FiltersBar`, `RoutesTable`, `Pagination` (Tasks 10–12). Skip build until Task 12.

- [ ] **Step 1: Create the page**

Create `admin/app/(dashboard)/routes/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/page.tsx
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { parseRoutesQuery } from "@/lib/routes/search-params";
import { FiltersBar } from "./filters-bar";
import { RoutesTable } from "./routes-table";
import { Pagination } from "./pagination";

export const dynamic = "force-dynamic";

export default async function RoutesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireAdmin();
  const q = parseRoutesQuery(await searchParams);
  const supabase = adminClient();

  let query = supabase
    .from("admin_routes_view")
    .select("*", { count: "exact" });

  if (q.search.trim() !== "") {
    const term = `%${q.search.trim()}%`;
    query = query.or(
      `name.ilike.${term},owner_nickname.ilike.${term},location_label.ilike.${term}`,
    );
  }
  if (q.difficulty !== "all") {
    query = query.eq("difficulty", q.difficulty);
  }
  if (q.official === "official") {
    query = query.eq("is_official", true);
  }
  if (q.official === "community") {
    query = query.eq("is_official", false);
  }

  query = query.order(q.sort, { ascending: q.dir === "asc" });
  const from = (q.page - 1) * q.pageSize;
  const to = from + q.pageSize - 1;
  query = query.range(from, to);

  const { data: rows, count, error } = await query;
  if (error) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold">Rutas</h1>
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
        <h1 className="text-2xl font-semibold">Rutas</h1>
        <p className="text-sm text-muted-foreground">
          {total} {total === 1 ? "ruta" : "rutas"} en total.
        </p>
      </div>
      <FiltersBar query={q} />
      <RoutesTable rows={rows ?? []} />
      <Pagination query={q} total={total} />
    </div>
  );
}
```

- [ ] **Step 2: Skip build (children pending)**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/routes/page.tsx"
git commit -m "feat(admin): /routes list page shell"
```

---

## Task 10: `FiltersBar` for `/routes`

**Files:**
- Create: `admin/app/(dashboard)/routes/filters-bar.tsx`

- [ ] **Step 1: Create the component**

Create `admin/app/(dashboard)/routes/filters-bar.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/filters-bar.tsx
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
  type DifficultyFilter,
  type OfficialFilter,
  serializeRoutesQuery,
  type RoutesQuery,
} from "@/lib/routes/search-params";

export function FiltersBar({ query }: { query: RoutesQuery }) {
  const router = useRouter();
  const pathname = usePathname();
  const [, startTransition] = useTransition();
  const [search, setSearch] = useState(query.search);

  useEffect(() => {
    if (search === query.search) return;
    const id = setTimeout(() => {
      startTransition(() => {
        router.push(
          pathname + serializeRoutesQuery(query, { search, page: 1 }),
        );
      });
    }, 300);
    return () => clearTimeout(id);
  }, [search, query, router, pathname]);

  function pushOverride(o: Partial<RoutesQuery>) {
    startTransition(() => {
      router.push(pathname + serializeRoutesQuery(query, { ...o, page: 1 }));
    });
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Input
        placeholder="Buscar por nombre, propietario o ubicación…"
        className="max-w-sm"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      <Select
        value={query.difficulty}
        onValueChange={(v) =>
          pushOverride({ difficulty: v as DifficultyFilter })
        }
      >
        <SelectTrigger className="w-40">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todas las dificultades</SelectItem>
          <SelectItem value="easy">easy</SelectItem>
          <SelectItem value="medium">medium</SelectItem>
          <SelectItem value="hard">hard</SelectItem>
          <SelectItem value="extreme">extreme</SelectItem>
        </SelectContent>
      </Select>
      <Select
        value={query.official}
        onValueChange={(v) => pushOverride({ official: v as OfficialFilter })}
      >
        <SelectTrigger className="w-36">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todas</SelectItem>
          <SelectItem value="official">Oficiales</SelectItem>
          <SelectItem value="community">Comunidad</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}
```

- [ ] **Step 2: Skip build**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/routes/filters-bar.tsx"
git commit -m "feat(admin): /routes filters bar"
```

---

## Task 11: `RoutesTable` with TanStack

**Files:**
- Create: `admin/app/(dashboard)/routes/routes-table.tsx`

- [ ] **Step 1: Create the table**

Create `admin/app/(dashboard)/routes/routes-table.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/routes-table.tsx
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
  parseRoutesQuery,
  serializeRoutesQuery,
  type SortKey,
} from "@/lib/routes/search-params";

type Row = {
  id: string | null;
  name: string | null;
  owner_nickname: string | null;
  difficulty: string | null;
  location_label: string | null;
  thumbnail_url: string | null;
  is_official: boolean | null;
  created_at: string | null;
  sectors_count: number | null;
  sessions_count: number | null;
};

function fmt(date: string | null): string {
  if (!date) return "—";
  const d = new Date(date);
  if (Number.isNaN(d.getTime())) return "—";
  return format(d, "dd/MM/yyyy");
}

export function RoutesTable({ rows }: { rows: Row[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseRoutesQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: SortKey) {
    const dir =
      query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeRoutesQuery(query, { sort: key, dir }));
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
      id: "thumbnail",
      header: "",
      cell: ({ row }) => (
        <div className="h-10 w-16 overflow-hidden rounded bg-muted">
          {row.original.thumbnail_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.original.thumbnail_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "name",
      header: () => <SortableHead label="Nombre" sortKey="name" />,
      cell: ({ row }) => (
        <div className="flex items-center gap-2">
          <span className="font-medium">{row.original.name || "—"}</span>
          {row.original.is_official ? (
            <Badge variant="default" className="text-xs">
              Oficial
            </Badge>
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "owner_nickname",
      header: "Propietario",
      cell: ({ row }) => row.original.owner_nickname ?? "—",
    },
    {
      accessorKey: "difficulty",
      header: () => <SortableHead label="Dificultad" sortKey="difficulty" />,
      cell: ({ row }) => (
        <Badge variant="outline">{row.original.difficulty ?? "—"}</Badge>
      ),
    },
    {
      accessorKey: "sectors_count",
      header: () => <SortableHead label="Sectores" sortKey="sectors_count" />,
      cell: ({ row }) => row.original.sectors_count ?? 0,
    },
    {
      accessorKey: "sessions_count",
      header: () => (
        <SortableHead label="Sesiones" sortKey="sessions_count" />
      ),
      cell: ({ row }) => row.original.sessions_count ?? 0,
    },
    {
      accessorKey: "location_label",
      header: "Ubicación",
      cell: ({ row }) => row.original.location_label ?? "—",
    },
    {
      accessorKey: "created_at",
      header: () => <SortableHead label="Creada" sortKey="created_at" />,
      cell: ({ row }) => fmt(row.original.created_at),
    },
  ];

  const table = useReactTable({
    data: rows,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

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
                    : flexRender(h.column.columnDef.header, h.getContext())}
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
                onClick={() => {
                  if (row.original.id) {
                    router.push(`/routes/${row.original.id}`);
                  }
                }}
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

- [ ] **Step 2: Skip build (pagination still pending)**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/routes/routes-table.tsx"
git commit -m "feat(admin): /routes TanStack table with sortable columns"
```

---

## Task 12: `Pagination` + list-page build check

**Files:**
- Create: `admin/app/(dashboard)/routes/pagination.tsx`

- [ ] **Step 1: Create the pager**

Create `admin/app/(dashboard)/routes/pagination.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/pagination.tsx
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
  serializeRoutesQuery,
  type RoutesQuery,
} from "@/lib/routes/search-params";

export function Pagination({
  query,
  total,
}: {
  query: RoutesQuery;
  total: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const totalPages = Math.max(1, Math.ceil(total / query.pageSize));

  function go(page: number) {
    router.push(pathname + serializeRoutesQuery(query, { page }));
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
                serializeRoutesQuery(query, {
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

- [ ] **Step 2: Build the list end-to-end**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. The `/routes` route should appear in the routes table.

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/routes/pagination.tsx"
git commit -m "feat(admin): /routes pagination + page-size selector"
```

---

## Task 13: Detail page Server Actions

**Files:**
- Create: `admin/app/(dashboard)/routes/[id]/actions.ts`

- [ ] **Step 1: Create the actions module**

Create `admin/app/(dashboard)/routes/[id]/actions.ts` with EXACTLY:

```ts
// admin/app/(dashboard)/routes/[id]/actions.ts
"use server";

import "server-only";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

// ---------- edit metadata ----------

const editSchema = z.object({
  routeId: z.string().uuid(),
  name: z.string().trim().min(1).max(120),
  description: z.string().max(2000).nullable(),
  difficulty: z.enum(["easy", "medium", "hard", "extreme"]),
  locationLabel: z.string().max(200).nullable(),
});

export type EditRouteState = { error?: string; ok?: boolean };

export async function editRoute(
  _prev: EditRouteState,
  formData: FormData,
): Promise<EditRouteState> {
  const admin = await requireAdmin();

  const parsed = editSchema.safeParse({
    routeId: formData.get("routeId"),
    name: formData.get("name"),
    description: formData.get("description") || null,
    difficulty: formData.get("difficulty"),
    locationLabel: formData.get("locationLabel") || null,
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { data: before } = await supabase
    .from("route_templates")
    .select("name, description, difficulty, location_label")
    .eq("id", parsed.data.routeId)
    .maybeSingle();

  const { error } = await supabase
    .from("route_templates")
    .update({
      name: parsed.data.name,
      description: parsed.data.description,
      difficulty: parsed.data.difficulty,
      location_label: parsed.data.locationLabel,
      updated_at: new Date().toISOString(),
    })
    .eq("id", parsed.data.routeId);
  if (error) return { error: "No se pudo guardar la ruta." };

  await writeAuditLog({
    adminId: admin.id,
    action: "edit_route",
    targetType: "route",
    targetId: parsed.data.routeId,
    details: {
      actorEmail: admin.email,
      before,
      after: {
        name: parsed.data.name,
        description: parsed.data.description,
        difficulty: parsed.data.difficulty,
        location_label: parsed.data.locationLabel,
      },
    },
  });

  revalidatePath(`/routes/${parsed.data.routeId}`);
  revalidatePath("/routes");
  return { ok: true };
}

// ---------- toggle is_official ----------

const toggleSchema = z.object({
  routeId: z.string().uuid(),
  isOfficial: z.coerce.boolean(),
});

export type ToggleOfficialState = { error?: string; ok?: boolean };

export async function toggleRouteOfficial(
  _prev: ToggleOfficialState,
  formData: FormData,
): Promise<ToggleOfficialState> {
  const admin = await requireAdmin();

  const rawIsOfficial = formData.get("isOfficial");
  const parsed = toggleSchema.safeParse({
    routeId: formData.get("routeId"),
    isOfficial: rawIsOfficial === "true" || rawIsOfficial === "1",
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { error } = await supabase
    .from("route_templates")
    .update({
      is_official: parsed.data.isOfficial,
      updated_at: new Date().toISOString(),
    })
    .eq("id", parsed.data.routeId);
  if (error) return { error: "No se pudo actualizar la ruta." };

  await writeAuditLog({
    adminId: admin.id,
    action: parsed.data.isOfficial
      ? "mark_route_official"
      : "unmark_route_official",
    targetType: "route",
    targetId: parsed.data.routeId,
    details: {
      actorEmail: admin.email,
      isOfficial: parsed.data.isOfficial,
    },
  });

  revalidatePath(`/routes/${parsed.data.routeId}`);
  revalidatePath("/routes");
  return { ok: true };
}

// ---------- duplicate as official ----------

const duplicateSchema = z.object({ routeId: z.string().uuid() });

export type DuplicateState = { error?: string };

export async function duplicateRouteAsOfficial(
  _prev: DuplicateState,
  formData: FormData,
): Promise<DuplicateState> {
  const admin = await requireAdmin();

  const parsed = duplicateSchema.safeParse({
    routeId: formData.get("routeId"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();
  const { data: newId, error } = await supabase.rpc(
    "duplicate_route_as_official",
    { p_source_route_id: parsed.data.routeId, p_admin_id: admin.id },
  );
  if (error || !newId) {
    return { error: "No se pudo duplicar la ruta." };
  }

  await writeAuditLog({
    adminId: admin.id,
    action: "duplicate_route",
    targetType: "route",
    targetId: newId as string,
    details: {
      actorEmail: admin.email,
      sourceRouteId: parsed.data.routeId,
    },
  });

  revalidatePath("/routes");
  redirect(`/routes/${newId}`);
}

// ---------- delete ----------

const deleteSchema = z.object({ routeId: z.string().uuid() });

export type DeleteRouteState = { error?: string };

export async function deleteRoute(
  _prev: DeleteRouteState,
  formData: FormData,
): Promise<DeleteRouteState> {
  const admin = await requireAdmin();

  const parsed = deleteSchema.safeParse({ routeId: formData.get("routeId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }

  const supabase = adminClient();

  // Capture the route name for the audit log before the row is gone.
  const { data: doomed } = await supabase
    .from("route_templates")
    .select("name, owner_id")
    .eq("id", parsed.data.routeId)
    .maybeSingle();

  const { error } = await supabase
    .from("route_templates")
    .delete()
    .eq("id", parsed.data.routeId);
  if (error) return { error: "No se pudo eliminar la ruta." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_route",
    targetType: "route",
    targetId: parsed.data.routeId,
    details: {
      actorEmail: admin.email,
      deletedName: doomed?.name,
      ownerId: doomed?.owner_id,
    },
  });

  revalidatePath("/routes");
  redirect("/routes");
}
```

- [ ] **Step 2: Skip build (detail page still pending)**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/routes/[id]/actions.ts"
git commit -m "feat(admin): route detail server actions (edit, toggle, duplicate, delete)"
```

---

## Task 14: Route map (client component)

**Files:**
- Create: `admin/app/(dashboard)/routes/[id]/route-map.tsx`

- [ ] **Step 1: Create the component**

Create `admin/app/(dashboard)/routes/[id]/route-map.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/[id]/route-map.tsx
"use client";

import { useEffect, useRef } from "react";
import "mapbox-gl/dist/mapbox-gl.css";

type Coord = [number, number]; // [longitude, latitude]

export function RouteMap({
  coordinates,
  className,
}: {
  coordinates: Coord[];
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;
    if (coordinates.length < 2) return;
    const token = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
    if (!token) {
      // eslint-disable-next-line no-console
      console.warn(
        "[RouteMap] NEXT_PUBLIC_MAPBOX_TOKEN is not set; map will not render.",
      );
      return;
    }

    let map: import("mapbox-gl").Map | null = null;
    let cancelled = false;

    void (async () => {
      const mapboxgl = (await import("mapbox-gl")).default;
      if (cancelled) return;
      mapboxgl.accessToken = token;

      const lons = coordinates.map((c) => c[0]);
      const lats = coordinates.map((c) => c[1]);
      const minLon = Math.min(...lons);
      const maxLon = Math.max(...lons);
      const minLat = Math.min(...lats);
      const maxLat = Math.max(...lats);

      map = new mapboxgl.Map({
        container: containerRef.current!,
        style: "mapbox://styles/mapbox/outdoors-v12",
        bounds: [
          [minLon, minLat],
          [maxLon, maxLat],
        ],
        fitBoundsOptions: { padding: 32 },
        attributionControl: false,
      });

      map.on("load", () => {
        if (!map || cancelled) return;
        map.addSource("route", {
          type: "geojson",
          data: {
            type: "Feature",
            properties: {},
            geometry: { type: "LineString", coordinates },
          },
        });
        map.addLayer({
          id: "route-line",
          type: "line",
          source: "route",
          layout: { "line-join": "round", "line-cap": "round" },
          paint: {
            "line-color": "#2563eb",
            "line-width": 4,
          },
        });
      });
    })();

    return () => {
      cancelled = true;
      map?.remove();
    };
  }, [coordinates]);

  if (coordinates.length < 2) {
    return (
      <div
        className={
          "flex h-72 items-center justify-center rounded-md border bg-muted text-sm text-muted-foreground " +
          (className ?? "")
        }
      >
        Esta ruta no tiene suficientes puntos para dibujar.
      </div>
    );
  }

  if (!process.env.NEXT_PUBLIC_MAPBOX_TOKEN) {
    return (
      <div
        className={
          "flex h-72 items-center justify-center rounded-md border bg-muted text-sm text-muted-foreground " +
          (className ?? "")
        }
      >
        Configura <code className="mx-1">NEXT_PUBLIC_MAPBOX_TOKEN</code> en{" "}
        <code className="mx-1">.env.local</code> para ver el mapa.
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className={"h-72 w-full overflow-hidden rounded-md border " + (className ?? "")}
    />
  );
}
```

- [ ] **Step 2: Skip build (detail page still pending)**

- [ ] **Step 3: Commit**

```powershell
git add "admin/app/(dashboard)/routes/[id]/route-map.tsx"
git commit -m "feat(admin): route detail Mapbox preview"
```

---

## Task 15: Metadata form + Official toggle + Delete dialog

**Files:**
- Create: `admin/app/(dashboard)/routes/[id]/metadata-form.tsx`
- Create: `admin/app/(dashboard)/routes/[id]/official-toggle.tsx`
- Create: `admin/app/(dashboard)/routes/[id]/delete-dialog.tsx`

### Step 1: Metadata form

Create `admin/app/(dashboard)/routes/[id]/metadata-form.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/[id]/metadata-form.tsx
"use client";

import { useActionState, useEffect } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { editRoute, type EditRouteState } from "./actions";

const initialState: EditRouteState = {};

export function MetadataForm({
  routeId,
  initialName,
  initialDescription,
  initialDifficulty,
  initialLocationLabel,
}: {
  routeId: string;
  initialName: string;
  initialDescription: string;
  initialDifficulty: string;
  initialLocationLabel: string;
}) {
  const [state, formAction, isPending] = useActionState(
    editRoute,
    initialState,
  );

  useEffect(() => {
    if (state.ok) toast.success("Ruta actualizada.");
  }, [state]);

  // The difficulty value is a string from the DB but the form's <Select>
  // is a controlled value mirrored into a hidden input on submit.
  return (
    <Card>
      <CardHeader>
        <CardTitle>Metadatos</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4">
          <input type="hidden" name="routeId" value={routeId} />
          <div className="space-y-2">
            <Label htmlFor="name">Nombre</Label>
            <Input
              id="name"
              name="name"
              defaultValue={initialName}
              maxLength={120}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="description">Descripción</Label>
            <textarea
              id="description"
              name="description"
              defaultValue={initialDescription}
              maxLength={2000}
              className="flex min-h-[80px] w-full rounded-md border bg-transparent px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="difficulty">Dificultad</Label>
            <select
              id="difficulty"
              name="difficulty"
              defaultValue={initialDifficulty}
              className="flex h-9 w-40 rounded-md border bg-transparent px-3 py-1 text-sm shadow-sm"
            >
              <option value="easy">easy</option>
              <option value="medium">medium</option>
              <option value="hard">hard</option>
              <option value="extreme">extreme</option>
            </select>
          </div>
          <div className="space-y-2">
            <Label htmlFor="locationLabel">Ubicación</Label>
            <Input
              id="locationLabel"
              name="locationLabel"
              defaultValue={initialLocationLabel}
              maxLength={200}
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

Note: I used a native `<select>` for difficulty instead of shadcn's `<Select>` because the value needs to land in `FormData` via the form. shadcn's Select doesn't render as a real `<select>` and won't submit the value without an extra hidden input. The native one is simpler here.

### Step 2: Official toggle

Create `admin/app/(dashboard)/routes/[id]/official-toggle.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/[id]/official-toggle.tsx
"use client";

import { useActionState, useEffect } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  toggleRouteOfficial,
  duplicateRouteAsOfficial,
  type ToggleOfficialState,
  type DuplicateState,
} from "./actions";

const initialToggle: ToggleOfficialState = {};
const initialDup: DuplicateState = {};

export function OfficialControls({
  routeId,
  isOfficial,
}: {
  routeId: string;
  isOfficial: boolean;
}) {
  const [toggleState, toggleAction, togglePending] = useActionState(
    toggleRouteOfficial,
    initialToggle,
  );
  const [dupState, dupAction, dupPending] = useActionState(
    duplicateRouteAsOfficial,
    initialDup,
  );

  useEffect(() => {
    if (toggleState.ok) {
      toast.success(
        isOfficial ? "Marca de oficial retirada." : "Ruta marcada como oficial.",
      );
    }
    if (toggleState.error) toast.error(toggleState.error);
  }, [toggleState, isOfficial]);

  useEffect(() => {
    if (dupState.error) toast.error(dupState.error);
  }, [dupState]);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Badge variant={isOfficial ? "default" : "outline"}>
        {isOfficial ? "Oficial" : "Comunidad"}
      </Badge>
      <form action={toggleAction}>
        <input type="hidden" name="routeId" value={routeId} />
        <input
          type="hidden"
          name="isOfficial"
          value={isOfficial ? "false" : "true"}
        />
        <Button type="submit" variant="outline" size="sm" disabled={togglePending}>
          {togglePending
            ? "Aplicando…"
            : isOfficial
              ? "Quitar marca oficial"
              : "Marcar como oficial"}
        </Button>
      </form>
      <form action={dupAction}>
        <input type="hidden" name="routeId" value={routeId} />
        <Button type="submit" variant="outline" size="sm" disabled={dupPending}>
          {dupPending ? "Duplicando…" : "Duplicar como oficial"}
        </Button>
      </form>
    </div>
  );
}
```

### Step 3: Delete dialog

Create `admin/app/(dashboard)/routes/[id]/delete-dialog.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/[id]/delete-dialog.tsx
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
import { deleteRoute, type DeleteRouteState } from "./actions";

const initialState: DeleteRouteState = {};

export function DeleteRouteDialog({
  routeId,
  routeName,
}: {
  routeId: string;
  routeName: string;
}) {
  const [state, formAction, isPending] = useActionState(
    deleteRoute,
    initialState,
  );

  useEffect(() => {
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Eliminar ruta</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Eliminar {routeName}</AlertDialogTitle>
          <AlertDialogDescription>
            Esta acción borrará la ruta y sus sectores. Las sesiones que
            apunten a ella quedarán huérfanas (route_id pasa a null). No se
            puede deshacer.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="routeId" value={routeId} />
          <AlertDialogFooter>
            <AlertDialogCancel type="button">Cancelar</AlertDialogCancel>
            <AlertDialogAction type="submit" disabled={isPending}>
              {isPending ? "Eliminando…" : "Eliminar"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}
```

- [ ] **Step 4: Single commit**

```powershell
git add "admin/app/(dashboard)/routes/[id]/metadata-form.tsx" "admin/app/(dashboard)/routes/[id]/official-toggle.tsx" "admin/app/(dashboard)/routes/[id]/delete-dialog.tsx"
git commit -m "feat(admin): route detail metadata form + official toggle + delete dialog"
```

---

## Task 16: Sectors card + Sessions card + Detail page + final build

**Files:**
- Create: `admin/app/(dashboard)/routes/[id]/sectors-card.tsx`
- Create: `admin/app/(dashboard)/routes/[id]/sessions-card.tsx`
- Create: `admin/app/(dashboard)/routes/[id]/page.tsx`

### Step 1: Sectors card (server component)

Create `admin/app/(dashboard)/routes/[id]/sectors-card.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/[id]/sectors-card.tsx
import { adminClient } from "@/lib/supabase/admin";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export async function SectorsCard({ routeId }: { routeId: string }) {
  const supabase = adminClient();
  const { data: sectors } = await supabase
    .from("sectors")
    .select("id, label, order_index")
    .eq("route_id", routeId)
    .order("order_index", { ascending: true });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sectores</CardTitle>
      </CardHeader>
      <CardContent>
        {!sectors || sectors.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sin sectores.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-16">#</TableHead>
                <TableHead>Etiqueta</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sectors.map((s) => (
                <TableRow key={s.id}>
                  <TableCell className="text-muted-foreground">
                    {s.order_index + 1}
                  </TableCell>
                  <TableCell>{s.label}</TableCell>
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

### Step 2: Sessions card (server component)

Create `admin/app/(dashboard)/routes/[id]/sessions-card.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/[id]/sessions-card.tsx
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

export async function SessionsCard({ routeId }: { routeId: string }) {
  const supabase = adminClient();
  const { data: sessions } = await supabase
    .from("session_runs")
    .select("id, owner_id, started_at, status, total_distance_m, avg_speed_mps")
    .eq("route_id", routeId)
    .order("started_at", { ascending: false })
    .limit(100);

  // Resolve owner nicknames in one extra query.
  const ownerIds = Array.from(
    new Set((sessions ?? []).map((s) => s.owner_id)),
  );
  const { data: owners } =
    ownerIds.length > 0
      ? await supabase
          .from("profiles")
          .select("id, nickname")
          .in("id", ownerIds)
      : { data: [] as { id: string; nickname: string }[] };
  const nicknameById = new Map(
    (owners ?? []).map((o) => [o.id, o.nickname] as const),
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sesiones recientes</CardTitle>
      </CardHeader>
      <CardContent>
        {!sessions || sessions.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Sin sesiones en esta ruta.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Usuario</TableHead>
                <TableHead className="w-32">Cuando</TableHead>
                <TableHead className="w-24">Estado</TableHead>
                <TableHead className="w-24 text-right">Dist. (m)</TableHead>
                <TableHead className="w-28 text-right">Vel. media</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sessions.map((s) => (
                <TableRow key={s.id}>
                  <TableCell>{nicknameById.get(s.owner_id) ?? "—"}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(s.started_at), "dd/MM/yyyy HH:mm")}
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline">{s.status}</Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    {Math.round(s.total_distance_m).toLocaleString("es-ES")}
                  </TableCell>
                  <TableCell className="text-right">
                    {(s.avg_speed_mps * 3.6).toFixed(1)} km/h
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

### Step 3: Detail page

Create `admin/app/(dashboard)/routes/[id]/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/routes/[id]/page.tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { MetadataForm } from "./metadata-form";
import { OfficialControls } from "./official-toggle";
import { DeleteRouteDialog } from "./delete-dialog";
import { RouteMap } from "./route-map";
import { SectorsCard } from "./sectors-card";
import { SessionsCard } from "./sessions-card";

export const dynamic = "force-dynamic";

type Coord = [number, number];

function toCoords(pathJson: unknown): Coord[] {
  if (!Array.isArray(pathJson)) return [];
  const out: Coord[] = [];
  for (const p of pathJson) {
    if (
      p &&
      typeof p === "object" &&
      "longitude" in p &&
      "latitude" in p &&
      typeof (p as { longitude: unknown }).longitude === "number" &&
      typeof (p as { latitude: unknown }).latitude === "number"
    ) {
      out.push([
        (p as { longitude: number }).longitude,
        (p as { latitude: number }).latitude,
      ]);
    }
  }
  return out;
}

export default async function RouteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("route_templates")
    .select(
      "id, name, description, difficulty, location_label, is_official, owner_id, path_json, created_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();

  const { data: owner } = await supabase
    .from("profiles")
    .select("nickname")
    .eq("id", row.owner_id)
    .maybeSingle();

  const coords = toCoords(row.path_json);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/routes">← Volver a rutas</Link>
      </Button>

      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">{row.name}</h1>
          {row.is_official ? <Badge variant="default">Oficial</Badge> : null}
          <Badge variant="outline">{row.difficulty}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          {row.location_label ? row.location_label + " · " : ""}
          Propietario:{" "}
          <span className="font-medium">{owner?.nickname ?? "—"}</span>
        </p>
      </div>

      <RouteMap coordinates={coords} />

      <OfficialControls routeId={row.id} isOfficial={row.is_official} />

      <MetadataForm
        routeId={row.id}
        initialName={row.name}
        initialDescription={row.description ?? ""}
        initialDifficulty={row.difficulty}
        initialLocationLabel={row.location_label ?? ""}
      />

      <SectorsCard routeId={row.id} />
      <SessionsCard routeId={row.id} />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteRouteDialog routeId={row.id} routeName={row.name} />
      </div>
    </div>
  );
}
```

### Step 4: Final build

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. The output should show both `/routes` and `/routes/[id]` in the routes table.

### Step 5: Commit

```powershell
git add "admin/app/(dashboard)/routes/[id]/"
git commit -m "feat(admin): /routes/[id] detail page with map, sectors, sessions"
```

---

## Task 17: Manual end-to-end verification

**Files:** none — verification only.

- [ ] **Step 1: Add the Mapbox token**

Open `admin/.env.local` and add a real Mapbox public token:
```env
NEXT_PUBLIC_MAPBOX_TOKEN=pk.xxxxxxxxxx
```

If you don't already have one, sign in at <https://account.mapbox.com/> and copy the "Default public token". Restart the container so the new env var is picked up:
```powershell
docker compose restart admin
```

- [ ] **Step 2: List page (criteria 1–6)**

1. Sign in as admin/superadmin. Click **Rutas** in the sidebar.
2. Confirm: header shows total count; 8 columns; thumbnails render (or empty boxes for routes without one); row click sends you to the detail page.
3. Type in the search box → after 300ms, table refetches with only matching rows. URL gains `?search=…`.
4. Change difficulty filter to `hard` → only hard routes. URL `&difficulty=hard`.
5. Change Official filter → table narrows accordingly. URL `&official=…`.
6. Click any sortable header (Nombre, Dificultad, Sectores, Sesiones, Creada) → toggles asc/desc. URL `&sort=…&dir=…`.
7. Page through results, switch page size.

- [ ] **Step 3: Detail header + map + sectors + sessions (criteria 7–8)**

1. Click a row to open `/routes/[id]`.
2. Header shows name, Oficial badge (if applicable), difficulty badge, location_label and owner nickname.
3. Mapbox map renders below with the route polyline drawn. Bounds fit the route. Drag/zoom works.
4. Sectores card lists every sector with its order. Sesiones recientes card lists at most 100 session_runs.

- [ ] **Step 4: Metadata edit (criterion 9)**

1. Change the name and submit.
2. Toast "Ruta actualizada" appears. Reload → name persists.
3. SQL:
   ```sql
   select action, target_id, details, created_at
   from public.admin_audit_log
   where action = 'edit_route'
   order by created_at desc limit 1;
   ```
   details has `actorEmail`, `before`, `after`.

- [ ] **Step 5: Mark / unmark official (criterion 10)**

1. Click **Marcar como oficial**. Badge flips to **Oficial**, button label changes to **Quitar marca oficial**. Toast.
2. SQL: `select * from public.admin_audit_log where action = 'mark_route_official' order by created_at desc limit 1;`
3. Click again → unmark, audit log gets `unmark_route_official`.

- [ ] **Step 6: Duplicate as official (criterion 11)**

1. Click **Duplicar como oficial**. Redirects to the new route's detail page.
2. New route shows `Oficial — <original name>`, is_official=true, sectors are cloned.
3. Owner is the current admin. Audit log gets `duplicate_route` with `sourceRouteId`.

- [ ] **Step 7: Delete (criterion 12)**

1. From the duplicated route's detail page, click **Eliminar ruta**, confirm in the dialog.
2. Redirects to `/routes`. The deleted route is gone from the list.
3. Audit log gets `delete_route` with `deletedName`.

- [ ] **Step 8: Done**

All 13 acceptance criteria pass → F4 complete. Hand off to `superpowers:finishing-a-development-branch`.

---

## Notes for the executor

- **`mapbox-gl` is bundled into the client.** Total addition is ~250 KB gzipped. The dynamic import in `route-map.tsx` keeps it out of pages that don't show the map.
- **`NEXT_PUBLIC_MAPBOX_TOKEN`** must be available at BUILD time AND at RUNTIME. The Docker build args / runtime env need to include it just like `NEXT_PUBLIC_SUPABASE_URL`.
- **`path_json` shape:** array of `{ latitude: number, longitude: number, altitudeMeters?: number }`. Mapbox wants `[longitude, latitude]` pairs — `toCoords()` in `page.tsx` handles the swap.
- **`session_runs.route_id` is a regular FK without ON DELETE.** When a route is deleted, Postgres will reject the delete IF there are session_runs referencing it — UNLESS the FK was declared with `ON DELETE SET NULL` or similar in the original schema. If your delete fails with FK violation, that's expected — F4 doesn't try to cascade; the spec acknowledges sessions can become orphaned. Verify against the actual schema; if it does cascade or restrict, update the DeleteRouteDialog description accordingly.
- **The `Official` filter uses `is_official`** which is a boolean — be aware that PostgREST's `.eq("is_official", true)` works correctly.
- **`duplicate_route_as_official`** is SECURITY DEFINER and grants only to `service_role`, so it can only be called from `adminClient()` (server-side, requireAdmin gate).
