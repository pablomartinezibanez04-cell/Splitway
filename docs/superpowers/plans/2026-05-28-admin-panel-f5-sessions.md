# Admin Panel — Phase F5 (Sessions) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `/sessions` admin surface — a tabbed list of every recorded session (timed `session_runs`, `free_rides`, drag-strip `speed_sessions`) with filters and a detail page per type (map of the recorded telemetry trace, speed-over-time + altitude-over-distance charts, sector splits, delete).

**Architecture:** One Server Component page (`/sessions`) hosts a shadcn Tabs container; the active tab is encoded in `?tab=`. Each tab is its own Server Component that fetches from a dedicated SQL view joining the session table with owner nickname + route name + vehicle name, applies filters/sort/pagination via URL params, and renders a TanStack Table. Detail pages live at `/sessions/{runs|free-rides|speed-sessions}/[id]` — the first two reuse F4's `RouteMap` (extended via re-export, no code change needed) plus two new Recharts charts; the speed-session detail is a metric-card layout reading the `results` JSONB. Every mutating action writes an `admin_audit_log` entry with `action = 'delete_session'`.

**Tech Stack:** Inherited from F4 — Next.js 16, `@supabase/ssr`, Zod, shadcn/ui, sonner, TanStack Table v8, date-fns, mapbox-gl. **New:** `recharts` for the two telemetry charts. No new shadcn components.

**Branch:** `feat/admin-sessions` (already created from `feat/admin-routes` so the F4 RouteMap component, search-params pattern, and audit helpers are in scope).

**Out of scope for F5 (handled later):**
- Editing session data (the spec is read-only except delete).
- Live-tail of sessions in progress (poll-based "active sessions" view; revisit if needed).
- Exporting telemetry as GPX/KML (CSV-export YAGNI per spec §2).
- Showing the route's polyline overlaid on the session trace for `session_runs` (would need a second `path_json` read; defer to keep this phase shippable).

**Acceptance criteria (verified in the final manual task, in the browser):**
1. Sidebar gains a **Sesiones** entry. Clicking it loads `/sessions` with the **Cronos** (session_runs) tab active by default.
2. Three tabs render: **Cronos** (session_runs), **Libres** (free_rides), **Velocidad** (speed_sessions). Switching tab updates `?tab=…` in the URL and the active tab's table refreshes.
3. Each tab table has columns appropriate to its type:
   - Cronos / Libres: usuario, vehículo, ruta (only for Cronos), fecha, duración, distancia, vel. media, vel. máxima.
   - Velocidad: usuario, vehículo, nombre, métricas, fecha, parcial (chip).
4. Free-text search (matches owner nickname or vehicle name) and date range filter (`from` / `to`) apply to the active tab. Debounced 300ms.
5. Server-side pagination + sort work per tab.
6. Clicking a row navigates to the detail page for that session type.
7. **Cronos detail** — Mapbox map renders the telemetry polyline; speed-over-time and altitude-over-distance charts render with axes labeled; the sector_summaries_json is shown as a small table with sector index, label, time, and avg speed; "Eliminar" button (with confirmation) deletes the session run + cascades telemetry, writes a `delete_session` audit entry, redirects to `/sessions?tab=runs`.
8. **Libre detail** — Same map and charts as Cronos (using `free_ride_telemetry`), no sector card, metadata header includes name / description / location_label; delete works the same.
9. **Velocidad detail** — Header with name + vehicle + admin who ran it; a grid of metric cards reading each entry of `results` JSONB (e.g. 0-100 km/h, 0-200 km/h, 400m); chip showing `is_partial`; delete works the same.
10. Every delete writes one audit row with `action='delete_session'`, `target_type='session'`, `details.type ∈ {'session_run', 'free_ride', 'speed_session'}`.

---

## File Structure

**New files:**

```
admin/
├── app/(dashboard)/sessions/
│   ├── page.tsx                              # tabs shell (Server Component)
│   ├── session-runs-tab.tsx                  # Cronos tab (server component)
│   ├── free-rides-tab.tsx                    # Libres tab
│   ├── speed-sessions-tab.tsx                # Velocidad tab
│   ├── filters-bar.tsx                       # shared filters (client)
│   ├── pagination.tsx                        # shared pager (client)
│   ├── runs-table.tsx                        # client TanStack for session_runs
│   ├── rides-table.tsx                       # client TanStack for free_rides
│   ├── speeds-table.tsx                      # client TanStack for speed_sessions
│   ├── runs/[id]/
│   │   ├── page.tsx                          # detail Server Component
│   │   ├── actions.ts                        # deleteSessionRun
│   │   ├── sector-summaries.tsx              # server component
│   │   └── delete-dialog.tsx                 # client confirm
│   ├── free-rides/[id]/
│   │   ├── page.tsx
│   │   ├── actions.ts                        # deleteFreeRide
│   │   └── delete-dialog.tsx
│   └── speed-sessions/[id]/
│       ├── page.tsx                          # metric-card layout
│       ├── actions.ts                        # deleteSpeedSession
│       ├── metrics-grid.tsx                  # server component
│       └── delete-dialog.tsx
├── components/shared/
│   ├── telemetry-charts.tsx                  # client; SpeedChart + AltitudeChart
│   └── (route-map.tsx already exists from F4 — reused)
└── lib/sessions/
    ├── search-params.ts                      # SessionsQuery + parse/serialize
    └── telemetry.ts                          # shared helpers (toCoords, distance)
supabase/migrations/
└── 20260601000007_admin_sessions_views.sql   # 3 views, service-role grant
```

**Modified files:**

- `admin/components/shared/sidebar.tsx` — add `/sessions` entry with the `Activity` lucide icon.
- `admin/lib/supabase/database.types.ts` — regenerated to include the three new views.
- `admin/package.json` + `admin/pnpm-lock.yaml` — add `recharts`.

---

## Task 1: SQL views for the three session types

**Files:**
- Create: `supabase/migrations/20260601000007_admin_sessions_views.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260601000007_admin_sessions_views.sql` with EXACTLY:

```sql
-- supabase/migrations/20260601000007_admin_sessions_views.sql
-- Three read-only views, one per session type, that the admin panel
-- queries directly to drive its /sessions tabs. Each view joins the
-- session table with the owner's profile and (when applicable) the
-- route and vehicle for filter-friendly display columns. Service-role
-- only — admins read via adminClient().

create or replace view public.admin_session_runs_view as
select
  s.id,
  s.owner_id,
  s.route_id,
  s.vehicle_id,
  s.started_at,
  s.ended_at,
  s.status,
  s.total_distance_m,
  s.avg_speed_mps,
  s.max_speed_mps,
  p.nickname as owner_nickname,
  rt.name as route_name,
  v.name as vehicle_name,
  extract(epoch from coalesce(s.ended_at, s.started_at) - s.started_at)::int
    as duration_seconds
from public.session_runs s
left join public.profiles p on p.id = s.owner_id
left join public.route_templates rt on rt.id = s.route_id
left join public.vehicles v on v.id = s.vehicle_id;

create or replace view public.admin_free_rides_view as
select
  s.id,
  s.owner_id,
  s.vehicle_id,
  s.name,
  s.description,
  s.location_label,
  s.started_at,
  s.ended_at,
  s.status,
  s.total_distance_m,
  s.avg_speed_mps,
  s.max_speed_mps,
  p.nickname as owner_nickname,
  v.name as vehicle_name,
  extract(epoch from coalesce(s.ended_at, s.started_at) - s.started_at)::int
    as duration_seconds
from public.free_rides s
left join public.profiles p on p.id = s.owner_id
left join public.vehicles v on v.id = s.vehicle_id;

create or replace view public.admin_speed_sessions_view as
select
  s.id,
  s.user_id as owner_id,
  s.vehicle_id,
  s.name,
  s.selected_metrics,
  s.results,
  s.countdown_seconds,
  s.is_partial,
  s.started_at,
  s.finished_at,
  s.created_at,
  p.nickname as owner_nickname,
  v.name as vehicle_name
from public.speed_sessions s
left join public.profiles p on p.id = s.user_id
left join public.vehicles v on v.id = s.vehicle_id
where s.deleted_at is null;

revoke all on public.admin_session_runs_view
  from public, anon, authenticated;
grant select on public.admin_session_runs_view to service_role;

revoke all on public.admin_free_rides_view
  from public, anon, authenticated;
grant select on public.admin_free_rides_view to service_role;

revoke all on public.admin_speed_sessions_view
  from public, anon, authenticated;
grant select on public.admin_speed_sessions_view to service_role;
```

- [ ] **Step 2: Apply to cloud**

```powershell
supabase db push
```

Expected: applies the migration, exits 0.

- [ ] **Step 3: Verify**

Run in the Supabase Dashboard SQL Editor:
```sql
select id, owner_nickname, route_name, vehicle_name, duration_seconds
from public.admin_session_runs_view limit 3;

select id, owner_nickname, vehicle_name, name, duration_seconds
from public.admin_free_rides_view limit 3;

select id, owner_nickname, vehicle_name, name, is_partial
from public.admin_speed_sessions_view limit 3;
```

Each should return rows (or empty if no data yet) with all columns populated.

- [ ] **Step 4: Commit**

```powershell
git add supabase/migrations/20260601000007_admin_sessions_views.sql
git commit -m "feat(db): admin_session_runs_view + admin_free_rides_view + admin_speed_sessions_view"
```

---

## Task 2: Regenerate `database.types.ts`

**Files:**
- Modify (regenerate): `admin/lib/supabase/database.types.ts`

- [ ] **Step 1: Regenerate**

```powershell
supabase gen types typescript --linked --schema public 2>$null > admin/lib/supabase/database.types.ts
```

Open the file and confirm `admin_session_runs_view`, `admin_free_rides_view`, and `admin_speed_sessions_view` appear under `public.Views`.

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
git commit -m "chore(admin): regenerate types for three admin_*_view session views"
```

---

## Task 3: Install Recharts + sidebar entry

**Files:**
- Modify: `admin/package.json`
- Modify: `admin/pnpm-lock.yaml`
- Modify: `admin/components/shared/sidebar.tsx`

- [ ] **Step 1: Install Recharts**

```powershell
cd admin
pnpm add recharts
cd ..
```

- [ ] **Step 2: Add sidebar entry**

Open `admin/components/shared/sidebar.tsx`. Add `Activity` to the lucide-react import and a `/sessions` entry between Rutas and Configuración:

```tsx
import { Activity, Home, Map, Settings, Users } from "lucide-react";

const NAV_ITEMS = [
  { href: "/", label: "Inicio", icon: Home },
  { href: "/users", label: "Usuarios", icon: Users },
  { href: "/routes", label: "Rutas", icon: Map },
  { href: "/sessions", label: "Sesiones", icon: Activity },
  { href: "/settings", label: "Configuración", icon: Settings },
] as const;
```

- [ ] **Step 3: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 4: Commit (two separate commits for hygiene)**

```powershell
git add admin/package.json admin/pnpm-lock.yaml
git commit -m "feat(admin): add recharts"

git add admin/components/shared/sidebar.tsx
git commit -m "feat(admin): sidebar entry for /sessions"
```

---

## Task 4: Shared search-params + telemetry helpers

**Files:**
- Create: `admin/lib/sessions/search-params.ts`
- Create: `admin/lib/sessions/telemetry.ts`

- [ ] **Step 1: search-params**

Create `admin/lib/sessions/search-params.ts` with EXACTLY:

```ts
// admin/lib/sessions/search-params.ts
// Shared URL state for the three /sessions tabs. `tab` controls
// which one is active; the rest are filter/sort/paging fields that
// apply to whichever tab is showing.

export type SessionTab = "runs" | "free-rides" | "speed-sessions";
export type SortDir = "asc" | "desc";

// Per-tab sort keys (each tab has different columns). The page picks
// a sane default per tab when none is specified.
export type RunsSortKey =
  | "started_at"
  | "duration_seconds"
  | "total_distance_m"
  | "avg_speed_mps"
  | "max_speed_mps";
export type RidesSortKey = RunsSortKey;
export type SpeedsSortKey =
  | "created_at"
  | "started_at"
  | "name"
  | "is_partial";
export type AnySortKey = RunsSortKey | RidesSortKey | SpeedsSortKey;

export type SessionsQuery = {
  tab: SessionTab;
  page: number;
  pageSize: number;
  search: string;
  from: string; // YYYY-MM-DD or "" (filters by started_at >= from)
  to: string; // YYYY-MM-DD or "" (filters by started_at <= to + 1 day)
  sort: AnySortKey;
  dir: SortDir;
};

const TABS: readonly SessionTab[] = ["runs", "free-rides", "speed-sessions"];
const DIRS: readonly SortDir[] = ["asc", "desc"];

const DEFAULT_SORT: Record<SessionTab, AnySortKey> = {
  runs: "started_at",
  "free-rides": "started_at",
  "speed-sessions": "created_at",
};

const SORT_WHITELIST: Record<SessionTab, readonly AnySortKey[]> = {
  runs: [
    "started_at",
    "duration_seconds",
    "total_distance_m",
    "avg_speed_mps",
    "max_speed_mps",
  ],
  "free-rides": [
    "started_at",
    "duration_seconds",
    "total_distance_m",
    "avg_speed_mps",
    "max_speed_mps",
  ],
  "speed-sessions": ["created_at", "started_at", "name", "is_partial"],
};

const DEFAULTS = {
  page: 1,
  pageSize: 25,
  search: "",
  from: "",
  to: "",
  dir: "desc" as SortDir,
};

function pickOne<T extends string>(
  raw: string | undefined,
  allowed: readonly T[],
  fallback: T,
): T {
  if (!raw) return fallback;
  return (allowed as readonly string[]).includes(raw) ? (raw as T) : fallback;
}

function isIsoDate(s: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(s);
}

export function parseSessionsQuery(
  searchParams: Record<string, string | string[] | undefined>,
): SessionsQuery {
  const raw = (key: string): string | undefined => {
    const v = searchParams[key];
    return Array.isArray(v) ? v[0] : v;
  };
  const tab = pickOne(raw("tab"), TABS, "runs");
  const sort = pickOne(raw("sort"), SORT_WHITELIST[tab], DEFAULT_SORT[tab]);
  const pageRaw = Number.parseInt(raw("page") ?? "", 10);
  const pageSizeRaw = Number.parseInt(raw("pageSize") ?? "", 10);
  const fromRaw = raw("from") ?? "";
  const toRaw = raw("to") ?? "";
  return {
    tab,
    page: Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : DEFAULTS.page,
    pageSize: [25, 50, 100].includes(pageSizeRaw)
      ? pageSizeRaw
      : DEFAULTS.pageSize,
    search: (raw("search") ?? DEFAULTS.search)
      .replace(/[,:]/g, " ")
      .slice(0, 100),
    from: isIsoDate(fromRaw) ? fromRaw : "",
    to: isIsoDate(toRaw) ? toRaw : "",
    sort,
    dir: pickOne(raw("dir"), DIRS, DEFAULTS.dir),
  };
}

export function serializeSessionsQuery(
  current: SessionsQuery,
  override: Partial<SessionsQuery>,
): string {
  const merged: SessionsQuery = { ...current, ...override };
  const params = new URLSearchParams();
  if (merged.tab !== "runs") params.set("tab", merged.tab);
  if (merged.page !== DEFAULTS.page) params.set("page", String(merged.page));
  if (merged.pageSize !== DEFAULTS.pageSize) {
    params.set("pageSize", String(merged.pageSize));
  }
  if (merged.search !== DEFAULTS.search) params.set("search", merged.search);
  if (merged.from) params.set("from", merged.from);
  if (merged.to) params.set("to", merged.to);
  if (merged.sort !== DEFAULT_SORT[merged.tab]) params.set("sort", merged.sort);
  if (merged.dir !== DEFAULTS.dir) params.set("dir", merged.dir);
  const s = params.toString();
  return s ? `?${s}` : "";
}
```

- [ ] **Step 2: telemetry helpers**

Create `admin/lib/sessions/telemetry.ts` with EXACTLY:

```ts
// admin/lib/sessions/telemetry.ts
// Pure helpers shared by the three detail pages. Both telemetry
// tables (telemetry_points and free_ride_telemetry) have the same
// row shape so a single set of helpers works.

export type TelemetryRow = {
  ts: string;
  lat: number;
  lng: number;
  altitude_m: number | null;
  speed_mps: number | null;
};

/** [lng, lat] pairs for Mapbox's LineString. */
export function toCoords(rows: TelemetryRow[]): [number, number][] {
  return rows.map((r) => [r.lng, r.lat]);
}

/** Haversine distance in meters between two lat/lng points. */
function haversineMeters(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** Cumulative distance (in meters) from row 0 to each subsequent row. */
export function cumulativeDistance(rows: TelemetryRow[]): number[] {
  const out: number[] = [];
  let total = 0;
  for (let i = 0; i < rows.length; i++) {
    if (i > 0) total += haversineMeters(rows[i - 1]!, rows[i]!);
    out.push(total);
  }
  return out;
}

/** Seconds elapsed from row 0 to each subsequent row. */
export function elapsedSeconds(rows: TelemetryRow[]): number[] {
  if (rows.length === 0) return [];
  const t0 = new Date(rows[0]!.ts).getTime();
  return rows.map((r) => (new Date(r.ts).getTime() - t0) / 1000);
}
```

- [ ] **Step 3: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

- [ ] **Step 4: Commit**

```powershell
git add admin/lib/sessions/
git commit -m "feat(admin): sessions search-params + telemetry helpers"
```

---

## Task 5: Shared filters + pagination components

**Files:**
- Create: `admin/app/(dashboard)/sessions/filters-bar.tsx`
- Create: `admin/app/(dashboard)/sessions/pagination.tsx`

- [ ] **Step 1: FiltersBar**

Create `admin/app/(dashboard)/sessions/filters-bar.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/filters-bar.tsx
"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, useTransition } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  serializeSessionsQuery,
  type SessionsQuery,
} from "@/lib/sessions/search-params";

export function FiltersBar({ query }: { query: SessionsQuery }) {
  const router = useRouter();
  const pathname = usePathname();
  const [, startTransition] = useTransition();
  const [search, setSearch] = useState(query.search);

  useEffect(() => {
    if (search === query.search) return;
    const id = setTimeout(() => {
      startTransition(() => {
        router.push(
          pathname + serializeSessionsQuery(query, { search, page: 1 }),
        );
      });
    }, 300);
    return () => clearTimeout(id);
  }, [search, query, router, pathname]);

  function pushDate(field: "from" | "to", value: string) {
    startTransition(() => {
      router.push(
        pathname +
          serializeSessionsQuery(query, { [field]: value, page: 1 } as Partial<SessionsQuery>),
      );
    });
  }

  return (
    <div className="flex flex-wrap items-end gap-3">
      <div className="flex-1 min-w-[220px] space-y-1">
        <Label htmlFor="sessions-search">Buscar</Label>
        <Input
          id="sessions-search"
          placeholder="usuario o vehículo…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>
      <div className="space-y-1">
        <Label htmlFor="sessions-from">Desde</Label>
        <Input
          id="sessions-from"
          type="date"
          value={query.from}
          onChange={(e) => pushDate("from", e.target.value)}
          className="w-44"
        />
      </div>
      <div className="space-y-1">
        <Label htmlFor="sessions-to">Hasta</Label>
        <Input
          id="sessions-to"
          type="date"
          value={query.to}
          onChange={(e) => pushDate("to", e.target.value)}
          className="w-44"
        />
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Pagination**

Create `admin/app/(dashboard)/sessions/pagination.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/pagination.tsx
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
  serializeSessionsQuery,
  type SessionsQuery,
} from "@/lib/sessions/search-params";

export function Pagination({
  query,
  total,
}: {
  query: SessionsQuery;
  total: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const totalPages = Math.max(1, Math.ceil(total / query.pageSize));

  function go(page: number) {
    router.push(pathname + serializeSessionsQuery(query, { page }));
  }

  return (
    <div className="flex items-center justify-between text-sm text-muted-foreground">
      <div>
        Página {query.page} de {totalPages} ({total} en total)
      </div>
      <div className="flex items-center gap-2">
        <Select
          value={String(query.pageSize)}
          onValueChange={(v) =>
            router.push(
              pathname +
                serializeSessionsQuery(query, {
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

- [ ] **Step 3: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

- [ ] **Step 4: Commit**

```powershell
git add "admin/app/(dashboard)/sessions/filters-bar.tsx" "admin/app/(dashboard)/sessions/pagination.tsx"
git commit -m "feat(admin): /sessions shared FiltersBar + Pagination"
```

---

## Task 6: Three table client components

**Files:**
- Create: `admin/app/(dashboard)/sessions/runs-table.tsx`
- Create: `admin/app/(dashboard)/sessions/rides-table.tsx`
- Create: `admin/app/(dashboard)/sessions/speeds-table.tsx`

- [ ] **Step 1: RunsTable**

Create `admin/app/(dashboard)/sessions/runs-table.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/runs-table.tsx
"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type ColumnDef,
} from "@tanstack/react-table";
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
  parseSessionsQuery,
  serializeSessionsQuery,
  type RunsSortKey,
} from "@/lib/sessions/search-params";

type Row = {
  id: string | null;
  owner_nickname: string | null;
  vehicle_name: string | null;
  route_name: string | null;
  started_at: string | null;
  ended_at: string | null;
  status: string | null;
  duration_seconds: number | null;
  total_distance_m: number | null;
  avg_speed_mps: number | null;
  max_speed_mps: number | null;
};

function fmtDate(s: string | null): string {
  if (!s) return "—";
  const ymd = s.slice(0, 10);
  const parts = ymd.split("-");
  if (parts.length !== 3) return "—";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

function fmtDuration(seconds: number | null): string {
  if (seconds == null || seconds <= 0) return "—";
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}m ${String(s).padStart(2, "0")}s`;
}

function fmtSpeed(mps: number | null): string {
  if (mps == null) return "—";
  return `${(mps * 3.6).toFixed(1)} km/h`;
}

export function RunsTable({ rows }: { rows: Row[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseSessionsQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: RunsSortKey) {
    const dir = query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeSessionsQuery(query, { sort: key, dir }));
  }

  function SortableHead({
    label,
    sortKey,
  }: {
    label: string;
    sortKey: RunsSortKey;
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
      accessorKey: "owner_nickname",
      header: "Usuario",
      cell: ({ row }) => row.original.owner_nickname ?? "—",
    },
    {
      accessorKey: "vehicle_name",
      header: "Vehículo",
      cell: ({ row }) => row.original.vehicle_name ?? "—",
    },
    {
      accessorKey: "route_name",
      header: "Ruta",
      cell: ({ row }) => row.original.route_name ?? "—",
    },
    {
      accessorKey: "started_at",
      header: () => <SortableHead label="Fecha" sortKey="started_at" />,
      cell: ({ row }) => fmtDate(row.original.started_at),
    },
    {
      accessorKey: "duration_seconds",
      header: () => <SortableHead label="Duración" sortKey="duration_seconds" />,
      cell: ({ row }) => fmtDuration(row.original.duration_seconds),
    },
    {
      accessorKey: "total_distance_m",
      header: () => (
        <SortableHead label="Distancia (m)" sortKey="total_distance_m" />
      ),
      cell: ({ row }) =>
        row.original.total_distance_m != null
          ? Math.round(row.original.total_distance_m).toLocaleString("es-ES")
          : "—",
    },
    {
      accessorKey: "avg_speed_mps",
      header: () => (
        <SortableHead label="Vel. media" sortKey="avg_speed_mps" />
      ),
      cell: ({ row }) => fmtSpeed(row.original.avg_speed_mps),
    },
    {
      accessorKey: "max_speed_mps",
      header: () => <SortableHead label="Vel. máx" sortKey="max_speed_mps" />,
      cell: ({ row }) => fmtSpeed(row.original.max_speed_mps),
    },
    {
      accessorKey: "status",
      header: "Estado",
      cell: ({ row }) => (
        <Badge variant="outline">{row.original.status ?? "—"}</Badge>
      ),
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
          {rows.length === 0 ? (
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
                    router.push(`/sessions/runs/${row.original.id}`);
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

- [ ] **Step 2: RidesTable**

Create `admin/app/(dashboard)/sessions/rides-table.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/rides-table.tsx
"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type ColumnDef,
} from "@tanstack/react-table";
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
  parseSessionsQuery,
  serializeSessionsQuery,
  type RidesSortKey,
} from "@/lib/sessions/search-params";

type Row = {
  id: string | null;
  owner_nickname: string | null;
  vehicle_name: string | null;
  name: string | null;
  location_label: string | null;
  started_at: string | null;
  ended_at: string | null;
  status: string | null;
  duration_seconds: number | null;
  total_distance_m: number | null;
  avg_speed_mps: number | null;
  max_speed_mps: number | null;
};

function fmtDate(s: string | null): string {
  if (!s) return "—";
  const ymd = s.slice(0, 10);
  const parts = ymd.split("-");
  if (parts.length !== 3) return "—";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

function fmtDuration(seconds: number | null): string {
  if (seconds == null || seconds <= 0) return "—";
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}m ${String(s).padStart(2, "0")}s`;
}

function fmtSpeed(mps: number | null): string {
  if (mps == null) return "—";
  return `${(mps * 3.6).toFixed(1)} km/h`;
}

export function RidesTable({ rows }: { rows: Row[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseSessionsQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: RidesSortKey) {
    const dir = query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeSessionsQuery(query, { sort: key, dir }));
  }

  function SortableHead({
    label,
    sortKey,
  }: {
    label: string;
    sortKey: RidesSortKey;
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
      accessorKey: "owner_nickname",
      header: "Usuario",
      cell: ({ row }) => row.original.owner_nickname ?? "—",
    },
    {
      accessorKey: "vehicle_name",
      header: "Vehículo",
      cell: ({ row }) => row.original.vehicle_name ?? "—",
    },
    {
      accessorKey: "name",
      header: "Nombre",
      cell: ({ row }) =>
        row.original.name || row.original.location_label || "—",
    },
    {
      accessorKey: "started_at",
      header: () => <SortableHead label="Fecha" sortKey="started_at" />,
      cell: ({ row }) => fmtDate(row.original.started_at),
    },
    {
      accessorKey: "duration_seconds",
      header: () => (
        <SortableHead label="Duración" sortKey="duration_seconds" />
      ),
      cell: ({ row }) => fmtDuration(row.original.duration_seconds),
    },
    {
      accessorKey: "total_distance_m",
      header: () => (
        <SortableHead label="Distancia (m)" sortKey="total_distance_m" />
      ),
      cell: ({ row }) =>
        row.original.total_distance_m != null
          ? Math.round(row.original.total_distance_m).toLocaleString("es-ES")
          : "—",
    },
    {
      accessorKey: "avg_speed_mps",
      header: () => (
        <SortableHead label="Vel. media" sortKey="avg_speed_mps" />
      ),
      cell: ({ row }) => fmtSpeed(row.original.avg_speed_mps),
    },
    {
      accessorKey: "max_speed_mps",
      header: () => <SortableHead label="Vel. máx" sortKey="max_speed_mps" />,
      cell: ({ row }) => fmtSpeed(row.original.max_speed_mps),
    },
    {
      accessorKey: "status",
      header: "Estado",
      cell: ({ row }) => (
        <Badge variant="outline">{row.original.status ?? "—"}</Badge>
      ),
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
          {rows.length === 0 ? (
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
                    router.push(`/sessions/free-rides/${row.original.id}`);
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

- [ ] **Step 3: SpeedsTable**

Create `admin/app/(dashboard)/sessions/speeds-table.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/speeds-table.tsx
"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type ColumnDef,
} from "@tanstack/react-table";
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
  parseSessionsQuery,
  serializeSessionsQuery,
  type SpeedsSortKey,
} from "@/lib/sessions/search-params";

type Row = {
  id: string | null;
  owner_nickname: string | null;
  vehicle_name: string | null;
  name: string | null;
  selected_metrics: string[] | null;
  is_partial: boolean | null;
  started_at: string | null;
  created_at: string | null;
};

function fmtDate(s: string | null): string {
  if (!s) return "—";
  const ymd = s.slice(0, 10);
  const parts = ymd.split("-");
  if (parts.length !== 3) return "—";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

export function SpeedsTable({ rows }: { rows: Row[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseSessionsQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: SpeedsSortKey) {
    const dir = query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeSessionsQuery(query, { sort: key, dir }));
  }

  function SortableHead({
    label,
    sortKey,
  }: {
    label: string;
    sortKey: SpeedsSortKey;
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
      accessorKey: "owner_nickname",
      header: "Usuario",
      cell: ({ row }) => row.original.owner_nickname ?? "—",
    },
    {
      accessorKey: "vehicle_name",
      header: "Vehículo",
      cell: ({ row }) => row.original.vehicle_name ?? "—",
    },
    {
      accessorKey: "name",
      header: () => <SortableHead label="Nombre" sortKey="name" />,
      cell: ({ row }) => row.original.name ?? "—",
    },
    {
      id: "metrics",
      header: "Métricas",
      cell: ({ row }) => (
        <div className="flex flex-wrap gap-1">
          {(row.original.selected_metrics ?? []).slice(0, 4).map((m) => (
            <Badge key={m} variant="outline" className="text-xs">
              {m}
            </Badge>
          ))}
          {(row.original.selected_metrics?.length ?? 0) > 4 ? (
            <span className="text-xs text-muted-foreground">
              +{(row.original.selected_metrics!.length - 4)}
            </span>
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "created_at",
      header: () => <SortableHead label="Creada" sortKey="created_at" />,
      cell: ({ row }) => fmtDate(row.original.created_at),
    },
    {
      accessorKey: "is_partial",
      header: () => <SortableHead label="Parcial" sortKey="is_partial" />,
      cell: ({ row }) =>
        row.original.is_partial ? (
          <Badge variant="secondary">Parcial</Badge>
        ) : (
          <Badge variant="outline">Completa</Badge>
        ),
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
          {rows.length === 0 ? (
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
                    router.push(`/sessions/speed-sessions/${row.original.id}`);
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

- [ ] **Step 4: Skip build (the tabs/page still pending)**

- [ ] **Step 5: Commit**

```powershell
git add "admin/app/(dashboard)/sessions/runs-table.tsx" "admin/app/(dashboard)/sessions/rides-table.tsx" "admin/app/(dashboard)/sessions/speeds-table.tsx"
git commit -m "feat(admin): /sessions three TanStack tables"
```

---

## Task 7: Three tab Server Components

**Files:**
- Create: `admin/app/(dashboard)/sessions/session-runs-tab.tsx`
- Create: `admin/app/(dashboard)/sessions/free-rides-tab.tsx`
- Create: `admin/app/(dashboard)/sessions/speed-sessions-tab.tsx`

Each tab is a Server Component that takes `{ query }` and fetches its slice of data.

- [ ] **Step 1: SessionRunsTab**

Create `admin/app/(dashboard)/sessions/session-runs-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/session-runs-tab.tsx
import { adminClient } from "@/lib/supabase/admin";
import type { SessionsQuery } from "@/lib/sessions/search-params";
import { RunsTable } from "./runs-table";
import { Pagination } from "./pagination";

export async function SessionRunsTab({ query }: { query: SessionsQuery }) {
  const supabase = adminClient();

  let q = supabase
    .from("admin_session_runs_view")
    .select("*", { count: "exact" });

  if (query.search.trim() !== "") {
    const term = `%${query.search.trim()}%`;
    q = q.or(`owner_nickname.ilike.${term},vehicle_name.ilike.${term}`);
  }
  if (query.from) {
    q = q.gte("started_at", `${query.from}T00:00:00Z`);
  }
  if (query.to) {
    q = q.lte("started_at", `${query.to}T23:59:59Z`);
  }

  q = q.order(query.sort, { ascending: query.dir === "asc" });
  const from = (query.page - 1) * query.pageSize;
  const to = from + query.pageSize - 1;
  q = q.range(from, to);

  const { data, count, error } = await q;
  if (error) {
    return (
      <p className="text-sm text-destructive">
        Error: {error.message}
      </p>
    );
  }

  return (
    <div className="space-y-4">
      <RunsTable rows={data ?? []} />
      <Pagination query={query} total={count ?? 0} />
    </div>
  );
}
```

- [ ] **Step 2: FreeRidesTab**

Create `admin/app/(dashboard)/sessions/free-rides-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/free-rides-tab.tsx
import { adminClient } from "@/lib/supabase/admin";
import type { SessionsQuery } from "@/lib/sessions/search-params";
import { RidesTable } from "./rides-table";
import { Pagination } from "./pagination";

export async function FreeRidesTab({ query }: { query: SessionsQuery }) {
  const supabase = adminClient();

  let q = supabase
    .from("admin_free_rides_view")
    .select("*", { count: "exact" });

  if (query.search.trim() !== "") {
    const term = `%${query.search.trim()}%`;
    q = q.or(
      `owner_nickname.ilike.${term},vehicle_name.ilike.${term},name.ilike.${term}`,
    );
  }
  if (query.from) {
    q = q.gte("started_at", `${query.from}T00:00:00Z`);
  }
  if (query.to) {
    q = q.lte("started_at", `${query.to}T23:59:59Z`);
  }

  q = q.order(query.sort, { ascending: query.dir === "asc" });
  const from = (query.page - 1) * query.pageSize;
  const to = from + query.pageSize - 1;
  q = q.range(from, to);

  const { data, count, error } = await q;
  if (error) {
    return (
      <p className="text-sm text-destructive">
        Error: {error.message}
      </p>
    );
  }

  return (
    <div className="space-y-4">
      <RidesTable rows={data ?? []} />
      <Pagination query={query} total={count ?? 0} />
    </div>
  );
}
```

- [ ] **Step 3: SpeedSessionsTab**

Create `admin/app/(dashboard)/sessions/speed-sessions-tab.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/speed-sessions-tab.tsx
import { adminClient } from "@/lib/supabase/admin";
import type { SessionsQuery } from "@/lib/sessions/search-params";
import { SpeedsTable } from "./speeds-table";
import { Pagination } from "./pagination";

export async function SpeedSessionsTab({ query }: { query: SessionsQuery }) {
  const supabase = adminClient();

  let q = supabase
    .from("admin_speed_sessions_view")
    .select("*", { count: "exact" });

  if (query.search.trim() !== "") {
    const term = `%${query.search.trim()}%`;
    q = q.or(
      `owner_nickname.ilike.${term},vehicle_name.ilike.${term},name.ilike.${term}`,
    );
  }
  // speed_sessions uses created_at; the date filter still applies to it
  // through the same `from`/`to` fields, mapped to created_at here.
  if (query.from) {
    q = q.gte("created_at", `${query.from}T00:00:00Z`);
  }
  if (query.to) {
    q = q.lte("created_at", `${query.to}T23:59:59Z`);
  }

  q = q.order(query.sort, { ascending: query.dir === "asc" });
  const from = (query.page - 1) * query.pageSize;
  const to = from + query.pageSize - 1;
  q = q.range(from, to);

  const { data, count, error } = await q;
  if (error) {
    return (
      <p className="text-sm text-destructive">
        Error: {error.message}
      </p>
    );
  }

  return (
    <div className="space-y-4">
      <SpeedsTable rows={data ?? []} />
      <Pagination query={query} total={count ?? 0} />
    </div>
  );
}
```

- [ ] **Step 4: Commit (skip build, the page shell still needs the tabs glue)**

```powershell
git add "admin/app/(dashboard)/sessions/session-runs-tab.tsx" "admin/app/(dashboard)/sessions/free-rides-tab.tsx" "admin/app/(dashboard)/sessions/speed-sessions-tab.tsx"
git commit -m "feat(admin): /sessions three tab Server Components"
```

---

## Task 8: `/sessions` page shell + build check

**Files:**
- Create: `admin/app/(dashboard)/sessions/page.tsx`
- Create: `admin/app/(dashboard)/sessions/tabs-switcher.tsx`

The switcher is a small client component that drives the active tab by updating `?tab=`.

- [ ] **Step 1: TabsSwitcher**

Create `admin/app/(dashboard)/sessions/tabs-switcher.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/tabs-switcher.tsx
"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  parseSessionsQuery,
  serializeSessionsQuery,
  type SessionTab,
} from "@/lib/sessions/search-params";

export function TabsSwitcher() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseSessionsQuery(Object.fromEntries(searchParams.entries()));

  function go(tab: SessionTab) {
    // Switching tab resets pagination + sort to that tab's defaults.
    router.push(
      pathname +
        serializeSessionsQuery(query, {
          tab,
          page: 1,
          sort:
            tab === "speed-sessions"
              ? "created_at"
              : "started_at",
        }),
    );
  }

  return (
    <Tabs value={query.tab} onValueChange={(v) => go(v as SessionTab)}>
      <TabsList>
        <TabsTrigger value="runs">Cronos</TabsTrigger>
        <TabsTrigger value="free-rides">Libres</TabsTrigger>
        <TabsTrigger value="speed-sessions">Velocidad</TabsTrigger>
      </TabsList>
    </Tabs>
  );
}
```

- [ ] **Step 2: Page**

Create `admin/app/(dashboard)/sessions/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/page.tsx
import { requireAdmin } from "@/lib/auth";
import { parseSessionsQuery } from "@/lib/sessions/search-params";
import { FiltersBar } from "./filters-bar";
import { TabsSwitcher } from "./tabs-switcher";
import { SessionRunsTab } from "./session-runs-tab";
import { FreeRidesTab } from "./free-rides-tab";
import { SpeedSessionsTab } from "./speed-sessions-tab";

export const dynamic = "force-dynamic";

export default async function SessionsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireAdmin();
  const query = parseSessionsQuery(await searchParams);

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Sesiones</h1>
        <p className="text-sm text-muted-foreground">
          Todas las sesiones grabadas por los usuarios.
        </p>
      </div>

      <TabsSwitcher />
      <FiltersBar query={query} />

      {query.tab === "runs" ? <SessionRunsTab query={query} /> : null}
      {query.tab === "free-rides" ? <FreeRidesTab query={query} /> : null}
      {query.tab === "speed-sessions" ? (
        <SpeedSessionsTab query={query} />
      ) : null}
    </div>
  );
}
```

- [ ] **Step 3: Run build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. `/sessions` should appear in the routes table.

- [ ] **Step 4: Commit**

```powershell
git add "admin/app/(dashboard)/sessions/page.tsx" "admin/app/(dashboard)/sessions/tabs-switcher.tsx"
git commit -m "feat(admin): /sessions tabbed list page"
```

---

## Task 9: Telemetry charts client component

**Files:**
- Create: `admin/components/shared/telemetry-charts.tsx`

Shared by the runs and free-ride detail pages. Recharts is dynamically imported so it doesn't bloat the list page.

- [ ] **Step 1: Create the component**

Create `admin/components/shared/telemetry-charts.tsx` with EXACTLY:

```tsx
// admin/components/shared/telemetry-charts.tsx
"use client";

import dynamic from "next/dynamic";
import {
  cumulativeDistance,
  elapsedSeconds,
  type TelemetryRow,
} from "@/lib/sessions/telemetry";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

// recharts pulls in d3 helpers — load it only when this component
// actually renders (detail page only, not the list).
const LineChart = dynamic(
  () => import("recharts").then((m) => m.LineChart),
  { ssr: false },
);
const Line = dynamic(() => import("recharts").then((m) => m.Line), {
  ssr: false,
});
const XAxis = dynamic(() => import("recharts").then((m) => m.XAxis), {
  ssr: false,
});
const YAxis = dynamic(() => import("recharts").then((m) => m.YAxis), {
  ssr: false,
});
const Tooltip = dynamic(() => import("recharts").then((m) => m.Tooltip), {
  ssr: false,
});
const ResponsiveContainer = dynamic(
  () => import("recharts").then((m) => m.ResponsiveContainer),
  { ssr: false },
);
const CartesianGrid = dynamic(
  () => import("recharts").then((m) => m.CartesianGrid),
  { ssr: false },
);

export function TelemetryCharts({ rows }: { rows: TelemetryRow[] }) {
  if (rows.length < 2) {
    return (
      <p className="text-sm text-muted-foreground">
        Sin telemetría suficiente para dibujar gráficas.
      </p>
    );
  }

  const distances = cumulativeDistance(rows);
  const seconds = elapsedSeconds(rows);

  const speedData = rows.map((r, i) => ({
    t: Math.round(seconds[i]!),
    speed: r.speed_mps != null ? +(r.speed_mps * 3.6).toFixed(1) : null,
  }));

  const altitudeData = rows.map((r, i) => ({
    d: Math.round(distances[i]!),
    altitude: r.altitude_m,
  }));

  return (
    <div className="grid gap-4 md:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Velocidad (km/h)</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart
                data={speedData}
                margin={{ top: 8, right: 8, left: 0, bottom: 8 }}
              >
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis
                  dataKey="t"
                  tickFormatter={(s) => `${Math.round(s / 60)}m`}
                  label={{ value: "tiempo", position: "insideBottomRight", offset: -4 }}
                />
                <YAxis />
                <Tooltip
                  formatter={(v: unknown) => [`${v} km/h`, "Velocidad"]}
                  labelFormatter={(s: unknown) =>
                    `t = ${typeof s === "number" ? Math.round(s) : 0} s`
                  }
                />
                <Line
                  type="monotone"
                  dataKey="speed"
                  stroke="#2563eb"
                  dot={false}
                  isAnimationActive={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Altitud (m)</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart
                data={altitudeData}
                margin={{ top: 8, right: 8, left: 0, bottom: 8 }}
              >
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis
                  dataKey="d"
                  tickFormatter={(m) => `${(m / 1000).toFixed(1)}km`}
                  label={{ value: "distancia", position: "insideBottomRight", offset: -4 }}
                />
                <YAxis />
                <Tooltip
                  formatter={(v: unknown) => [`${v ?? "—"} m`, "Altitud"]}
                  labelFormatter={(d: unknown) =>
                    `dist = ${typeof d === "number" ? Math.round(d) : 0} m`
                  }
                />
                <Line
                  type="monotone"
                  dataKey="altitude"
                  stroke="#16a34a"
                  dot={false}
                  isAnimationActive={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>
    </div>
  );
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
git add admin/components/shared/telemetry-charts.tsx
git commit -m "feat(admin): TelemetryCharts (speed + altitude, recharts)"
```

---

## Task 10: Session run detail page

**Files:**
- Create: `admin/app/(dashboard)/sessions/runs/[id]/actions.ts`
- Create: `admin/app/(dashboard)/sessions/runs/[id]/delete-dialog.tsx`
- Create: `admin/app/(dashboard)/sessions/runs/[id]/sector-summaries.tsx`
- Create: `admin/app/(dashboard)/sessions/runs/[id]/page.tsx`

- [ ] **Step 1: actions.ts**

Create `admin/app/(dashboard)/sessions/runs/[id]/actions.ts` with EXACTLY:

```ts
// admin/app/(dashboard)/sessions/runs/[id]/actions.ts
"use server";

import "server-only";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

const schema = z.object({
  sessionId: z.string().regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "ID inválido.",
  ),
});

export type DeleteState = { error?: string };

export async function deleteSessionRun(
  _prev: DeleteState,
  formData: FormData,
): Promise<DeleteState> {
  const admin = await requireAdmin();
  const parsed = schema.safeParse({ sessionId: formData.get("sessionId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }
  const supabase = adminClient();

  const { data: doomed } = await supabase
    .from("session_runs")
    .select("owner_id, started_at")
    .eq("id", parsed.data.sessionId)
    .maybeSingle();

  const { error } = await supabase
    .from("session_runs")
    .delete()
    .eq("id", parsed.data.sessionId);
  if (error) return { error: "No se pudo eliminar la sesión." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_session",
    targetType: "session",
    targetId: parsed.data.sessionId,
    details: {
      actorEmail: admin.email,
      type: "session_run",
      ownerId: doomed?.owner_id,
      startedAt: doomed?.started_at,
    },
  });

  revalidatePath("/sessions");
  redirect("/sessions?tab=runs");
}
```

- [ ] **Step 2: delete-dialog.tsx**

Create `admin/app/(dashboard)/sessions/runs/[id]/delete-dialog.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/runs/[id]/delete-dialog.tsx
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
import { deleteSessionRun, type DeleteState } from "./actions";

const initialState: DeleteState = {};

export function DeleteSessionRunDialog({ sessionId }: { sessionId: string }) {
  const [state, formAction, isPending] = useActionState(
    deleteSessionRun,
    initialState,
  );
  useEffect(() => {
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Eliminar sesión</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Eliminar sesión cronometrada</AlertDialogTitle>
          <AlertDialogDescription>
            Se borrará la sesión y todos sus puntos de telemetría
            (<code className="rounded bg-muted px-1">ON DELETE CASCADE</code>).
            No se puede deshacer.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="sessionId" value={sessionId} />
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

- [ ] **Step 3: sector-summaries.tsx**

Create `admin/app/(dashboard)/sessions/runs/[id]/sector-summaries.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/runs/[id]/sector-summaries.tsx
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type SectorSummary = {
  sectorId?: string;
  label?: string;
  index?: number;
  timeMs?: number;
  avgSpeedMps?: number;
};

function parseSectors(json: unknown): SectorSummary[] {
  if (!Array.isArray(json)) return [];
  return json.filter((x): x is SectorSummary => typeof x === "object" && x !== null);
}

export function SectorSummaries({ json }: { json: unknown }) {
  const sectors = parseSectors(json);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Sectores</CardTitle>
      </CardHeader>
      <CardContent>
        {sectors.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Sin información de sectores.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-12">#</TableHead>
                <TableHead>Etiqueta</TableHead>
                <TableHead className="text-right">Tiempo</TableHead>
                <TableHead className="text-right">Vel. media</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sectors.map((s, i) => (
                <TableRow key={s.sectorId ?? i}>
                  <TableCell className="text-muted-foreground">
                    {(s.index ?? i) + 1}
                  </TableCell>
                  <TableCell>{s.label ?? "—"}</TableCell>
                  <TableCell className="text-right">
                    {s.timeMs != null
                      ? `${(s.timeMs / 1000).toFixed(2)} s`
                      : "—"}
                  </TableCell>
                  <TableCell className="text-right">
                    {s.avgSpeedMps != null
                      ? `${(s.avgSpeedMps * 3.6).toFixed(1)} km/h`
                      : "—"}
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

- [ ] **Step 4: page.tsx**

Create `admin/app/(dashboard)/sessions/runs/[id]/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/runs/[id]/page.tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { RouteMap } from "@/app/(dashboard)/routes/[id]/route-map";
import { TelemetryCharts } from "@/components/shared/telemetry-charts";
import { toCoords, type TelemetryRow } from "@/lib/sessions/telemetry";
import { SectorSummaries } from "./sector-summaries";
import { DeleteSessionRunDialog } from "./delete-dialog";

export const dynamic = "force-dynamic";

export default async function SessionRunDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  // Fetch from session_runs directly because the view doesn't expose
  // sector_summaries_json. Joins are done as separate one-shot lookups
  // — cheap for a detail page.
  const { data: row } = await supabase
    .from("session_runs")
    .select(
      "id, owner_id, route_id, vehicle_id, started_at, ended_at, status, sector_summaries_json",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();

  const [{ data: profile }, { data: routeRow }, { data: vehicle }] =
    await Promise.all([
      supabase
        .from("profiles")
        .select("nickname")
        .eq("id", row.owner_id)
        .maybeSingle(),
      row.route_id
        ? supabase
            .from("route_templates")
            .select("name")
            .eq("id", row.route_id)
            .maybeSingle()
        : Promise.resolve({ data: null as { name: string } | null }),
      row.vehicle_id
        ? supabase
            .from("vehicles")
            .select("name")
            .eq("id", row.vehicle_id)
            .maybeSingle()
        : Promise.resolve({ data: null as { name: string } | null }),
    ]);

  const { data: telemetry } = await supabase
    .from("telemetry_points")
    .select("ts, lat, lng, altitude_m, speed_mps")
    .eq("session_id", id)
    .order("ts", { ascending: true });

  const rows: TelemetryRow[] = (telemetry ?? []).map((r) => ({
    ts: r.ts,
    lat: r.lat,
    lng: r.lng,
    altitude_m: r.altitude_m,
    speed_mps: r.speed_mps,
  }));

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/sessions?tab=runs">← Volver a sesiones</Link>
      </Button>

      <div className="space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">
            Sesión de {profile?.nickname ?? "—"}
          </h1>
          <Badge variant="outline">{row.status ?? "—"}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          Ruta: <span className="font-medium">{routeRow?.name ?? "—"}</span>
          {vehicle?.name ? ` · Vehículo: ${vehicle.name}` : ""}
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recorrido</CardTitle>
        </CardHeader>
        <CardContent>
          <RouteMap coordinates={toCoords(rows)} />
        </CardContent>
      </Card>

      <TelemetryCharts rows={rows} />

      <SectorSummaries json={row.sector_summaries_json ?? null} />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteSessionRunDialog sessionId={id} />
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 6: Commit**

```powershell
git add "admin/app/(dashboard)/sessions/runs/"
git commit -m "feat(admin): /sessions/runs/[id] detail (map + charts + sectors + delete)"
```

---

## Task 11: Free-ride detail page

**Files:**
- Create: `admin/app/(dashboard)/sessions/free-rides/[id]/actions.ts`
- Create: `admin/app/(dashboard)/sessions/free-rides/[id]/delete-dialog.tsx`
- Create: `admin/app/(dashboard)/sessions/free-rides/[id]/page.tsx`

- [ ] **Step 1: actions.ts**

Create `admin/app/(dashboard)/sessions/free-rides/[id]/actions.ts` with EXACTLY:

```ts
// admin/app/(dashboard)/sessions/free-rides/[id]/actions.ts
"use server";

import "server-only";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

const schema = z.object({
  freeRideId: z.string().regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "ID inválido.",
  ),
});

export type DeleteState = { error?: string };

export async function deleteFreeRide(
  _prev: DeleteState,
  formData: FormData,
): Promise<DeleteState> {
  const admin = await requireAdmin();
  const parsed = schema.safeParse({ freeRideId: formData.get("freeRideId") });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }
  const supabase = adminClient();

  const { data: doomed } = await supabase
    .from("free_rides")
    .select("owner_id, started_at, name")
    .eq("id", parsed.data.freeRideId)
    .maybeSingle();

  const { error } = await supabase
    .from("free_rides")
    .delete()
    .eq("id", parsed.data.freeRideId);
  if (error) return { error: "No se pudo eliminar la salida." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_session",
    targetType: "session",
    targetId: parsed.data.freeRideId,
    details: {
      actorEmail: admin.email,
      type: "free_ride",
      ownerId: doomed?.owner_id,
      startedAt: doomed?.started_at,
      name: doomed?.name,
    },
  });

  revalidatePath("/sessions");
  redirect("/sessions?tab=free-rides");
}
```

- [ ] **Step 2: delete-dialog.tsx**

Create `admin/app/(dashboard)/sessions/free-rides/[id]/delete-dialog.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/free-rides/[id]/delete-dialog.tsx
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
import { deleteFreeRide, type DeleteState } from "./actions";

const initialState: DeleteState = {};

export function DeleteFreeRideDialog({ freeRideId }: { freeRideId: string }) {
  const [state, formAction, isPending] = useActionState(
    deleteFreeRide,
    initialState,
  );
  useEffect(() => {
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Eliminar salida</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Eliminar salida libre</AlertDialogTitle>
          <AlertDialogDescription>
            Se borrará la salida y todos sus puntos de telemetría
            (<code className="rounded bg-muted px-1">ON DELETE CASCADE</code>).
            No se puede deshacer.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="freeRideId" value={freeRideId} />
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

- [ ] **Step 3: page.tsx**

Create `admin/app/(dashboard)/sessions/free-rides/[id]/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/free-rides/[id]/page.tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { RouteMap } from "@/app/(dashboard)/routes/[id]/route-map";
import { TelemetryCharts } from "@/components/shared/telemetry-charts";
import { toCoords, type TelemetryRow } from "@/lib/sessions/telemetry";
import { DeleteFreeRideDialog } from "./delete-dialog";

export const dynamic = "force-dynamic";

export default async function FreeRideDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("free_rides")
    .select(
      "id, owner_id, vehicle_id, name, description, location_label, started_at, ended_at, status",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();

  const [{ data: profile }, { data: vehicle }] = await Promise.all([
    supabase.from("profiles").select("nickname").eq("id", row.owner_id).maybeSingle(),
    row.vehicle_id
      ? supabase.from("vehicles").select("name").eq("id", row.vehicle_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  const { data: telemetry } = await supabase
    .from("free_ride_telemetry")
    .select("ts, lat, lng, altitude_m, speed_mps")
    .eq("free_ride_id", id)
    .order("ts", { ascending: true });

  const rows: TelemetryRow[] = (telemetry ?? []).map((r) => ({
    ts: r.ts,
    lat: r.lat,
    lng: r.lng,
    altitude_m: r.altitude_m,
    speed_mps: r.speed_mps,
  }));

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/sessions?tab=free-rides">← Volver a sesiones</Link>
      </Button>

      <div className="space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">
            {row.name || row.location_label || "Salida libre"}
          </h1>
          <Badge variant="outline">{row.status ?? "—"}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          Usuario: <span className="font-medium">{profile?.nickname ?? "—"}</span>
          {vehicle?.name ? ` · Vehículo: ${vehicle.name}` : ""}
        </p>
        {row.description ? (
          <p className="text-sm text-muted-foreground">{row.description}</p>
        ) : null}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recorrido</CardTitle>
        </CardHeader>
        <CardContent>
          <RouteMap coordinates={toCoords(rows)} />
        </CardContent>
      </Card>

      <TelemetryCharts rows={rows} />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteFreeRideDialog freeRideId={id} />
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Verify build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green.

- [ ] **Step 5: Commit**

```powershell
git add "admin/app/(dashboard)/sessions/free-rides/"
git commit -m "feat(admin): /sessions/free-rides/[id] detail (map + charts + delete)"
```

---

## Task 12: Speed-session detail page

**Files:**
- Create: `admin/app/(dashboard)/sessions/speed-sessions/[id]/actions.ts`
- Create: `admin/app/(dashboard)/sessions/speed-sessions/[id]/delete-dialog.tsx`
- Create: `admin/app/(dashboard)/sessions/speed-sessions/[id]/metrics-grid.tsx`
- Create: `admin/app/(dashboard)/sessions/speed-sessions/[id]/page.tsx`

- [ ] **Step 1: actions.ts**

Create `admin/app/(dashboard)/sessions/speed-sessions/[id]/actions.ts` with EXACTLY:

```ts
// admin/app/(dashboard)/sessions/speed-sessions/[id]/actions.ts
"use server";

import "server-only";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { writeAuditLog } from "@/lib/audit";

const schema = z.object({
  speedSessionId: z.string().regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
    "ID inválido.",
  ),
});

export type DeleteState = { error?: string };

export async function deleteSpeedSession(
  _prev: DeleteState,
  formData: FormData,
): Promise<DeleteState> {
  const admin = await requireAdmin();
  const parsed = schema.safeParse({
    speedSessionId: formData.get("speedSessionId"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Datos inválidos." };
  }
  const supabase = adminClient();

  const { data: doomed } = await supabase
    .from("speed_sessions")
    .select("user_id, name, created_at")
    .eq("id", parsed.data.speedSessionId)
    .maybeSingle();

  // Use soft-delete: speed_sessions has deleted_at, the view filters it out.
  const { error } = await supabase
    .from("speed_sessions")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", parsed.data.speedSessionId);
  if (error) return { error: "No se pudo eliminar la sesión." };

  await writeAuditLog({
    adminId: admin.id,
    action: "delete_session",
    targetType: "session",
    targetId: parsed.data.speedSessionId,
    details: {
      actorEmail: admin.email,
      type: "speed_session",
      userId: doomed?.user_id,
      name: doomed?.name,
      createdAt: doomed?.created_at,
    },
  });

  revalidatePath("/sessions");
  redirect("/sessions?tab=speed-sessions");
}
```

- [ ] **Step 2: delete-dialog.tsx**

Create `admin/app/(dashboard)/sessions/speed-sessions/[id]/delete-dialog.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/speed-sessions/[id]/delete-dialog.tsx
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
import { deleteSpeedSession, type DeleteState } from "./actions";

const initialState: DeleteState = {};

export function DeleteSpeedSessionDialog({
  speedSessionId,
}: {
  speedSessionId: string;
}) {
  const [state, formAction, isPending] = useActionState(
    deleteSpeedSession,
    initialState,
  );
  useEffect(() => {
    if (state.error) toast.error(state.error);
  }, [state]);

  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button variant="destructive">Eliminar sesión</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Eliminar sesión de velocidad</AlertDialogTitle>
          <AlertDialogDescription>
            La fila quedará marcada como borrada (<code className="rounded bg-muted px-1">deleted_at</code>) y dejará de aparecer en la lista. La cuenta del usuario y los datos crudos se preservan por si hubiera una disputa.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form action={formAction}>
          <input type="hidden" name="speedSessionId" value={speedSessionId} />
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

- [ ] **Step 3: metrics-grid.tsx**

Create `admin/app/(dashboard)/sessions/speed-sessions/[id]/metrics-grid.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/speed-sessions/[id]/metrics-grid.tsx
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

type Results = Record<string, { value: number | null; unit?: string }>;

function parseResults(json: unknown): Results {
  if (!json || typeof json !== "object" || Array.isArray(json)) return {};
  const out: Results = {};
  for (const [k, v] of Object.entries(json as Record<string, unknown>)) {
    if (v && typeof v === "object" && "value" in v) {
      const obj = v as { value?: unknown; unit?: unknown };
      out[k] = {
        value: typeof obj.value === "number" ? obj.value : null,
        unit: typeof obj.unit === "string" ? obj.unit : undefined,
      };
    } else if (typeof v === "number") {
      out[k] = { value: v };
    }
  }
  return out;
}

export function MetricsGrid({ json }: { json: unknown }) {
  const results = parseResults(json);
  const entries = Object.entries(results);
  if (entries.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Esta sesión no registró ninguna métrica.
      </p>
    );
  }
  return (
    <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-3">
      {entries.map(([key, m]) => (
        <Card key={key}>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground">
              {key}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold">
              {m.value != null ? m.value.toFixed(2) : "—"}
              {m.unit ? (
                <span className="ml-1 text-sm text-muted-foreground">
                  {m.unit}
                </span>
              ) : null}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
```

- [ ] **Step 4: page.tsx**

Create `admin/app/(dashboard)/sessions/speed-sessions/[id]/page.tsx` with EXACTLY:

```tsx
// admin/app/(dashboard)/sessions/speed-sessions/[id]/page.tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { MetricsGrid } from "./metrics-grid";
import { DeleteSpeedSessionDialog } from "./delete-dialog";

export const dynamic = "force-dynamic";

export default async function SpeedSessionDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("speed_sessions")
    .select(
      "id, user_id, vehicle_id, name, selected_metrics, results, countdown_seconds, is_partial, started_at, finished_at, created_at, deleted_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row || row.deleted_at != null) notFound();

  const [{ data: profile }, { data: vehicle }] = await Promise.all([
    supabase.from("profiles").select("nickname").eq("id", row.user_id).maybeSingle(),
    row.vehicle_id
      ? supabase.from("vehicles").select("name").eq("id", row.vehicle_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/sessions?tab=speed-sessions">← Volver a sesiones</Link>
      </Button>

      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">{row.name}</h1>
          {row.is_partial ? (
            <Badge variant="secondary">Parcial</Badge>
          ) : (
            <Badge variant="outline">Completa</Badge>
          )}
        </div>
        <p className="text-sm text-muted-foreground">
          Usuario: <span className="font-medium">{profile?.nickname ?? "—"}</span>
          {vehicle?.name ? ` · Vehículo: ${vehicle.name}` : ""}
        </p>
        <p className="text-xs text-muted-foreground">
          Métricas seleccionadas:{" "}
          {(row.selected_metrics ?? []).join(", ") || "—"}
        </p>
      </div>

      <MetricsGrid json={row.results} />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteSpeedSessionDialog speedSessionId={id} />
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Verify final build**

```powershell
cd admin
pnpm build
cd ..
```

Expected: green. The routes table should show:
```
ƒ /sessions
ƒ /sessions/free-rides/[id]
ƒ /sessions/runs/[id]
ƒ /sessions/speed-sessions/[id]
```

- [ ] **Step 6: Commit**

```powershell
git add "admin/app/(dashboard)/sessions/speed-sessions/"
git commit -m "feat(admin): /sessions/speed-sessions/[id] detail (metrics + delete)"
```

---

## Task 13: Manual end-to-end verification

**Files:** none — verification only.

- [ ] **Step 1: Start the panel**

```powershell
cd admin
docker compose up      # or pnpm dev
```

- [ ] **Step 2: List page (criteria 1–6)**

1. Sign in as admin. Click **Sesiones** in the sidebar. Default tab is **Cronos**.
2. Confirm three tabs render and switching updates `?tab=…`.
3. In each tab, the columns match criterion 3.
4. Type a user nickname in **Buscar** → after 300ms the table filters. URL gains `&search=…`. Clear it.
5. Pick a **Desde** date → table filters to that date onward. Same for **Hasta**.
6. Click a sortable header → toggles ASC/DESC, URL `&sort=…&dir=…`.
7. Pagination + page-size selector work.

- [ ] **Step 3: Cronos detail (criterion 7)**

1. Click a session-run row. Header shows owner nickname, status badge, route + vehicle.
2. Map renders the telemetry polyline (requires `NEXT_PUBLIC_MAPBOX_TOKEN`).
3. Speed-vs-time and altitude-vs-distance charts render.
4. Sector summaries table appears (or "Sin información" if the session has none).
5. Click **Eliminar sesión** → confirm → redirected to `/sessions?tab=runs`, the row is gone.
6. SQL:
   ```sql
   select action, target_id, details->>'type' as kind
   from public.admin_audit_log
   where action = 'delete_session'
   order by created_at desc limit 5;
   ```
   The latest row is `type=session_run`.

- [ ] **Step 4: Libre detail (criterion 8)**

1. Open a free-ride row. Same checks: map, charts, delete.
2. Audit row has `type=free_ride`.

- [ ] **Step 5: Velocidad detail (criterion 9)**

1. Open a speed-session row. Header has name + chip Parcial / Completa.
2. Metric cards render one per key of `results` jsonb.
3. Delete soft-deletes (sets `deleted_at`). The row disappears from the list.
4. Audit row has `type=speed_session`.

- [ ] **Step 6: Done**

If all 10 acceptance criteria pass → F5 complete. Hand off to `superpowers:finishing-a-development-branch`.

---

## Notes for the executor

- **The three list tables look very similar.** They share the same `fmt*` helpers but are kept as separate files because the columns and target routes differ enough that extracting a generic table would obscure intent. Resist the urge to merge them.
- **`RouteMap` is reused as-is.** It takes `[lng, lat][]` and draws a line; that's exactly what we need for telemetry too. Future enhancement could overlay route polyline + telemetry trace simultaneously on `session_runs` detail.
- **speed_sessions uses soft delete** (`deleted_at`). The view filters out rows with non-null `deleted_at`. The other two tables hard-delete.
- **Date filtering** uses `started_at` for runs and free_rides; for speed_sessions it uses `created_at` (because `started_at` can be null for unfinished partial sessions).
- **`delete_session` is already in the AuditAction union** (in the "Reserved" block from F2's audit.ts). No need to extend it.
- **No tests in this phase** per spec §9.
