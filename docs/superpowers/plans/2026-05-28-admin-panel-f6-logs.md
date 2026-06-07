# Admin Panel F6 — Logs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Sentry-style log viewer at `/logs` over `public.app_logs`, with multi-field filters, server-side pagination, a virtualized table, a slide-over detail panel, and a live-tail toggle that polls every 5 seconds.

**Architecture:** New SQL view `admin_app_logs_view` joins `app_logs` with `profiles.nickname` so the UI can show a human-readable user without a second query per row. The page is a Server Component that parses URL state via `parseLogsQuery`, fetches one page from the view through `adminClient()`, and hands rows to a client component that:
- Renders a virtualized TanStack-Virtual table.
- Opens a shadcn `Sheet` with `stack_trace`, a collapsible JSON tree of `context`, and `device_model` when a row is clicked.
- Toggles a 5-second polling loop that calls a Server Action `fetchNewerLogs(filters, sinceIso)` and prepends new rows above the current list.

**Tech Stack:** Next.js 16 App Router, Server Components + Server Actions, Supabase service-role client, TanStack Virtual, shadcn/ui (Sheet primitive added in Task 3), Zod validation, sonner toasts.

---

## File Structure

**New SQL:**
- `supabase/migrations/20260601000008_admin_app_logs_view.sql`

**New TypeScript / TSX:**
- `admin/lib/logs/search-params.ts` — URL state parser/serializer
- `admin/app/(dashboard)/logs/page.tsx` — server shell
- `admin/app/(dashboard)/logs/filters-bar.tsx` — client component, debounced inputs + selects
- `admin/app/(dashboard)/logs/logs-view.tsx` — client component, owns the virtualized table + live-tail state
- `admin/app/(dashboard)/logs/log-detail-sheet.tsx` — slide-over with stack/context/device
- `admin/app/(dashboard)/logs/actions.ts` — `fetchNewerLogs` Server Action

**Modified:**
- `admin/components/shared/sidebar.tsx` — add `/logs` entry
- `admin/lib/supabase/database.types.ts` — regenerated
- `admin/components/ui/sheet.tsx` — added via shadcn add

---

## Task 1: SQL view `admin_app_logs_view`

**Files:**
- Create: `supabase/migrations/20260601000008_admin_app_logs_view.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260601000008_admin_app_logs_view.sql
-- Admin-only view over public.app_logs with the user's nickname
-- joined in for display. Service-role-only access — RLS on the
-- underlying table already restricts SELECT to service_role, but we
-- repeat the grants explicitly on the view so a future change to
-- app_logs RLS doesn't accidentally expose this.

drop view if exists public.admin_app_logs_view;

create view public.admin_app_logs_view as
select
  l.id,
  l.timestamp,
  l.level,
  l.tag,
  l.message,
  l.error,
  l.stack_trace,
  l.context,
  l.app_version,
  l.platform,
  l.device_model,
  l.user_id,
  p.nickname as user_nickname
from public.app_logs l
left join public.profiles p on p.id = l.user_id;

revoke all on public.admin_app_logs_view from public;
revoke all on public.admin_app_logs_view from anon;
revoke all on public.admin_app_logs_view from authenticated;
grant select on public.admin_app_logs_view to service_role;
```

- [ ] **Step 2: Apply the migration**

Run: `docker compose exec db psql -U postgres -d postgres -f /migrations/20260601000008_admin_app_logs_view.sql`
(or via Supabase Dashboard SQL editor against the cloud project, same way previous F4/F5 migrations were applied).

Expected: `CREATE VIEW`, four `REVOKE`/`GRANT` lines, no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260601000008_admin_app_logs_view.sql
git commit -m "feat(db): admin_app_logs_view (logs + nickname, service-role only)"
```

---

## Task 2: Regenerate `database.types.ts`

**Files:**
- Modify: `admin/lib/supabase/database.types.ts`

- [ ] **Step 1: Regenerate types from the cloud project**

```bash
cd admin
pnpm supabase gen types typescript --project-id "$SUPABASE_PROJECT_ID" --schema public > lib/supabase/database.types.ts
cd ..
```

- [ ] **Step 2: Verify the new view is present**

Grep for `admin_app_logs_view`. Expect it to appear once under `Views`.

- [ ] **Step 3: Commit**

```bash
git add admin/lib/supabase/database.types.ts
git commit -m "chore(admin): regenerate db types with admin_app_logs_view"
```

---

## Task 3: Install `@tanstack/react-virtual` + add shadcn `sheet` + sidebar entry

**Files:**
- Modify: `admin/package.json`, `admin/pnpm-lock.yaml`
- Create: `admin/components/ui/sheet.tsx` (via shadcn cli)
- Modify: `admin/components/shared/sidebar.tsx`

- [ ] **Step 1: Install the virtualizer**

```bash
cd admin
pnpm add @tanstack/react-virtual
```

- [ ] **Step 2: Add the shadcn `sheet` primitive**

```bash
cd admin
pnpm dlx shadcn@latest add sheet
```

Expected: `admin/components/ui/sheet.tsx` created.

- [ ] **Step 3: Add `/logs` to the sidebar between Sesiones and Configuración**

Edit `admin/components/shared/sidebar.tsx` so `NAV_ITEMS` reads exactly:

```tsx
import { Activity, FileText, Home, Map, Settings, Users } from "lucide-react";

const NAV_ITEMS = [
  { href: "/", label: "Inicio", icon: Home },
  { href: "/users", label: "Usuarios", icon: Users },
  { href: "/routes", label: "Rutas", icon: Map },
  { href: "/sessions", label: "Sesiones", icon: Activity },
  { href: "/logs", label: "Logs", icon: FileText },
  { href: "/settings", label: "Configuración", icon: Settings },
] as const;
```

- [ ] **Step 4: Commit**

```bash
git add admin/package.json admin/pnpm-lock.yaml admin/components/ui/sheet.tsx admin/components/shared/sidebar.tsx
git commit -m "feat(admin): install react-virtual + shadcn sheet, sidebar /logs entry"
```

---

## Task 4: `admin/lib/logs/search-params.ts`

**Files:**
- Create: `admin/lib/logs/search-params.ts`

- [ ] **Step 1: Write the helper**

```ts
// admin/lib/logs/search-params.ts
// URL state for /logs. Mirrors the helper-per-feature pattern used
// by users, routes, and sessions. The page passes the parsed query
// straight to the Server Component and serializes it back when the
// user edits a filter.

export type LogLevel = "debug" | "info" | "warning" | "error";

export type LogsQuery = {
  page: number;
  pageSize: number;
  levels: LogLevel[];       // empty array = all levels
  tag: string;
  userId: string;           // accepts free text (uuid or partial)
  appVersion: string;
  platform: string;         // ios | android | "" = all
  search: string;           // matches message ILIKE %search%
  from: string;             // YYYY-MM-DD or ""
  to: string;               // YYYY-MM-DD or ""
};

const ALL_LEVELS: readonly LogLevel[] = ["debug", "info", "warning", "error"];
const PAGE_SIZES = [50, 100, 250] as const;

const DEFAULTS = {
  page: 1,
  pageSize: 100,
  tag: "",
  userId: "",
  appVersion: "",
  platform: "",
  search: "",
  from: "",
  to: "",
};

function isIsoDate(s: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(s);
}

function parseLevels(raw: string | undefined): LogLevel[] {
  if (!raw) return [];
  const parts = raw
    .split(",")
    .map((s) => s.trim())
    .filter((s): s is LogLevel => (ALL_LEVELS as readonly string[]).includes(s));
  // Deduplicate while preserving order.
  return Array.from(new Set(parts));
}

export function parseLogsQuery(
  searchParams: Record<string, string | string[] | undefined>,
): LogsQuery {
  const raw = (key: string): string | undefined => {
    const v = searchParams[key];
    return Array.isArray(v) ? v[0] : v;
  };
  const pageRaw = Number.parseInt(raw("page") ?? "", 10);
  const pageSizeRaw = Number.parseInt(raw("pageSize") ?? "", 10);
  const fromRaw = raw("from") ?? "";
  const toRaw = raw("to") ?? "";

  return {
    page: Number.isFinite(pageRaw) && pageRaw > 0 ? pageRaw : DEFAULTS.page,
    pageSize: (PAGE_SIZES as readonly number[]).includes(pageSizeRaw)
      ? pageSizeRaw
      : DEFAULTS.pageSize,
    levels: parseLevels(raw("levels")),
    tag: (raw("tag") ?? DEFAULTS.tag).slice(0, 100),
    userId: (raw("userId") ?? DEFAULTS.userId).slice(0, 100),
    appVersion: (raw("appVersion") ?? DEFAULTS.appVersion).slice(0, 50),
    platform: (raw("platform") ?? DEFAULTS.platform).slice(0, 20),
    search: (raw("search") ?? DEFAULTS.search).slice(0, 200),
    from: isIsoDate(fromRaw) ? fromRaw : "",
    to: isIsoDate(toRaw) ? toRaw : "",
  };
}

export function serializeLogsQuery(
  current: LogsQuery,
  override: Partial<LogsQuery>,
): string {
  const merged: LogsQuery = { ...current, ...override };
  const params = new URLSearchParams();
  if (merged.page !== DEFAULTS.page) params.set("page", String(merged.page));
  if (merged.pageSize !== DEFAULTS.pageSize) {
    params.set("pageSize", String(merged.pageSize));
  }
  if (merged.levels.length > 0) params.set("levels", merged.levels.join(","));
  if (merged.tag) params.set("tag", merged.tag);
  if (merged.userId) params.set("userId", merged.userId);
  if (merged.appVersion) params.set("appVersion", merged.appVersion);
  if (merged.platform) params.set("platform", merged.platform);
  if (merged.search) params.set("search", merged.search);
  if (merged.from) params.set("from", merged.from);
  if (merged.to) params.set("to", merged.to);
  const s = params.toString();
  return s ? `?${s}` : "";
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/lib/logs/search-params.ts
git commit -m "feat(admin): logs URL state helper"
```

---

## Task 5: `actions.ts` — `fetchNewerLogs` Server Action

**Files:**
- Create: `admin/app/(dashboard)/logs/actions.ts`

- [ ] **Step 1: Write the action**

```ts
// admin/app/(dashboard)/logs/actions.ts
"use server";

import "server-only";

import { z } from "zod";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import type { LogLevel } from "@/lib/logs/search-params";

// The shape returned to the client. Keep it explicit (don't reuse the
// generated Database row type) so a column rename in the view becomes
// a compile error here.
export type LogRow = {
  id: string;
  timestamp: string;
  level: LogLevel;
  tag: string;
  message: string;
  error: string | null;
  stack_trace: string | null;
  context: unknown;
  app_version: string;
  platform: string;
  device_model: string;
  user_id: string | null;
  user_nickname: string | null;
};

const filtersSchema = z.object({
  levels: z.array(z.enum(["debug", "info", "warning", "error"])).default([]),
  tag: z.string().max(100).default(""),
  userId: z.string().max(100).default(""),
  appVersion: z.string().max(50).default(""),
  platform: z.string().max(20).default(""),
  search: z.string().max(200).default(""),
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal("")).default(""),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).or(z.literal("")).default(""),
  sinceIso: z.string().datetime(),
  limit: z.number().int().min(1).max(500).default(100),
});

export type FetchNewerInput = z.infer<typeof filtersSchema>;

export async function fetchNewerLogs(
  input: FetchNewerInput,
): Promise<{ ok: true; rows: LogRow[] } | { ok: false; error: string }> {
  await requireAdmin();
  const parsed = filtersSchema.safeParse(input);
  if (!parsed.success) {
    return { ok: false, error: "Filtros inválidos." };
  }
  const f = parsed.data;
  const supabase = adminClient();
  let q = supabase
    .from("admin_app_logs_view")
    .select(
      "id, timestamp, level, tag, message, error, stack_trace, context, app_version, platform, device_model, user_id, user_nickname",
    )
    .gt("timestamp", f.sinceIso)
    .order("timestamp", { ascending: false })
    .limit(f.limit);

  if (f.levels.length > 0) q = q.in("level", f.levels);
  if (f.tag) q = q.ilike("tag", `%${f.tag}%`);
  if (f.userId) q = q.eq("user_id", f.userId);
  if (f.appVersion) q = q.ilike("app_version", `%${f.appVersion}%`);
  if (f.platform) q = q.eq("platform", f.platform);
  if (f.search) q = q.ilike("message", `%${f.search}%`);
  if (f.from) q = q.gte("timestamp", `${f.from}T00:00:00.000Z`);
  if (f.to) {
    const to = new Date(`${f.to}T00:00:00.000Z`);
    to.setUTCDate(to.getUTCDate() + 1);
    q = q.lt("timestamp", to.toISOString());
  }

  const { data, error } = await q;
  if (error) return { ok: false, error: error.message };
  return { ok: true, rows: (data ?? []) as LogRow[] };
}
```

- [ ] **Step 2: Commit**

```bash
git add admin/app/(dashboard)/logs/actions.ts
git commit -m "feat(admin): fetchNewerLogs Server Action for live tail"
```

---

## Task 6: `filters-bar.tsx`

**Files:**
- Create: `admin/app/(dashboard)/logs/filters-bar.tsx`

- [ ] **Step 1: Write the client component**

```tsx
// admin/app/(dashboard)/logs/filters-bar.tsx
"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  type LogLevel,
  type LogsQuery,
  serializeLogsQuery,
} from "@/lib/logs/search-params";

const LEVELS: LogLevel[] = ["debug", "info", "warning", "error"];

export function FiltersBar({ query }: { query: LogsQuery }) {
  const router = useRouter();
  const [search, setSearch] = useState(query.search);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Debounced free-text search.
  useEffect(() => {
    if (search === query.search) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      router.push(`/logs${serializeLogsQuery(query, { search, page: 1 })}`);
    }, 300);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  function toggleLevel(level: LogLevel) {
    const next = query.levels.includes(level)
      ? query.levels.filter((l) => l !== level)
      : [...query.levels, level];
    router.push(`/logs${serializeLogsQuery(query, { levels: next, page: 1 })}`);
  }

  function setField(key: keyof LogsQuery, value: string) {
    router.push(
      `/logs${serializeLogsQuery(query, { [key]: value, page: 1 } as Partial<LogsQuery>)}`,
    );
  }

  return (
    <div className="space-y-3 rounded-lg border bg-card p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm text-muted-foreground">Niveles:</span>
        {LEVELS.map((l) => {
          const active = query.levels.includes(l);
          return (
            <Badge
              key={l}
              variant={active ? "default" : "outline"}
              className="cursor-pointer select-none"
              onClick={() => toggleLevel(l)}
            >
              {l}
            </Badge>
          );
        })}
      </div>

      <div className="grid gap-3 md:grid-cols-3 lg:grid-cols-4">
        <div className="space-y-1">
          <Label htmlFor="logs-search">Mensaje</Label>
          <Input
            id="logs-search"
            placeholder="Buscar…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-tag">Tag</Label>
          <Input
            id="logs-tag"
            placeholder="auth, route_editor…"
            defaultValue={query.tag}
            onBlur={(e) => {
              const v = e.target.value.trim();
              if (v !== query.tag) setField("tag", v);
            }}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-user">User ID</Label>
          <Input
            id="logs-user"
            placeholder="UUID…"
            defaultValue={query.userId}
            onBlur={(e) => {
              const v = e.target.value.trim();
              if (v !== query.userId) setField("userId", v);
            }}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-version">App version</Label>
          <Input
            id="logs-version"
            placeholder="1.2.3"
            defaultValue={query.appVersion}
            onBlur={(e) => {
              const v = e.target.value.trim();
              if (v !== query.appVersion) setField("appVersion", v);
            }}
          />
        </div>
        <div className="space-y-1">
          <Label>Plataforma</Label>
          <Select
            value={query.platform || "all"}
            onValueChange={(v) => setField("platform", v === "all" ? "" : v)}
          >
            <SelectTrigger>
              <SelectValue placeholder="Todas" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todas</SelectItem>
              <SelectItem value="ios">iOS</SelectItem>
              <SelectItem value="android">Android</SelectItem>
              <SelectItem value="web">Web</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-from">Desde</Label>
          <Input
            id="logs-from"
            type="date"
            defaultValue={query.from}
            onChange={(e) => setField("from", e.target.value)}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-to">Hasta</Label>
          <Input
            id="logs-to"
            type="date"
            defaultValue={query.to}
            onChange={(e) => setField("to", e.target.value)}
          />
        </div>
        <div className="flex items-end">
          <Button
            type="button"
            variant="ghost"
            onClick={() => router.push("/logs")}
          >
            Limpiar
          </Button>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add "admin/app/(dashboard)/logs/filters-bar.tsx"
git commit -m "feat(admin): /logs filters bar"
```

---

## Task 7: `log-detail-sheet.tsx` (slide-over)

**Files:**
- Create: `admin/app/(dashboard)/logs/log-detail-sheet.tsx`

- [ ] **Step 1: Write the component**

```tsx
// admin/app/(dashboard)/logs/log-detail-sheet.tsx
"use client";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Badge } from "@/components/ui/badge";
import type { LogRow } from "./actions";

const LEVEL_VARIANT: Record<
  LogRow["level"],
  "default" | "secondary" | "destructive" | "outline"
> = {
  debug: "outline",
  info: "secondary",
  warning: "default",
  error: "destructive",
};

export function LogDetailSheet({
  row,
  onOpenChange,
}: {
  row: LogRow | null;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Sheet open={row != null} onOpenChange={onOpenChange}>
      <SheetContent className="w-full max-w-2xl overflow-y-auto sm:max-w-2xl">
        {row ? (
          <>
            <SheetHeader>
              <SheetTitle className="flex flex-wrap items-center gap-2">
                <Badge variant={LEVEL_VARIANT[row.level]}>{row.level}</Badge>
                <span className="font-mono text-xs text-muted-foreground">
                  {row.tag}
                </span>
              </SheetTitle>
              <SheetDescription className="text-foreground">
                {row.message}
              </SheetDescription>
            </SheetHeader>

            <div className="mt-6 space-y-6 text-sm">
              <Section label="Timestamp">
                <code className="font-mono">{row.timestamp}</code>
              </Section>
              <Section label="Usuario">
                {row.user_nickname ? (
                  <>
                    <span className="font-medium">{row.user_nickname}</span>{" "}
                    <span className="text-xs text-muted-foreground">
                      ({row.user_id ?? "—"})
                    </span>
                  </>
                ) : row.user_id ? (
                  <code className="font-mono text-xs">{row.user_id}</code>
                ) : (
                  <span className="text-muted-foreground">anónimo</span>
                )}
              </Section>
              <Section label="Plataforma">
                {row.platform} · {row.device_model} · v{row.app_version}
              </Section>
              {row.error ? (
                <Section label="Error">
                  <pre className="whitespace-pre-wrap rounded bg-muted p-2 text-xs">
                    {row.error}
                  </pre>
                </Section>
              ) : null}
              {row.stack_trace ? (
                <Section label="Stack trace">
                  <pre className="max-h-80 overflow-auto whitespace-pre rounded bg-muted p-2 font-mono text-xs leading-relaxed">
                    {row.stack_trace}
                  </pre>
                </Section>
              ) : null}
              {row.context != null ? (
                <Section label="Contexto">
                  <pre className="max-h-80 overflow-auto whitespace-pre-wrap rounded bg-muted p-2 font-mono text-xs">
                    {JSON.stringify(row.context, null, 2)}
                  </pre>
                </Section>
              ) : null}
            </div>
          </>
        ) : null}
      </SheetContent>
    </Sheet>
  );
}

function Section({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <div className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        {label}
      </div>
      <div>{children}</div>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add "admin/app/(dashboard)/logs/log-detail-sheet.tsx"
git commit -m "feat(admin): /logs slide-over detail sheet"
```

---

## Task 8: `logs-view.tsx` (virtualized table + live tail wiring)

**Files:**
- Create: `admin/app/(dashboard)/logs/logs-view.tsx`

- [ ] **Step 1: Write the component**

```tsx
// admin/app/(dashboard)/logs/logs-view.tsx
"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useVirtualizer } from "@tanstack/react-virtual";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  type LogsQuery,
  serializeLogsQuery,
} from "@/lib/logs/search-params";
import { fetchNewerLogs, type LogRow } from "./actions";
import { LogDetailSheet } from "./log-detail-sheet";

const LEVEL_BADGE: Record<
  LogRow["level"],
  "default" | "secondary" | "destructive" | "outline"
> = {
  debug: "outline",
  info: "secondary",
  warning: "default",
  error: "destructive",
};

function fmtTime(iso: string): string {
  // Trim sub-second precision and Z suffix for compact display.
  // Hydration-stable: pure string slicing, no timezone math.
  return iso.replace("T", " ").replace(/\.\d+/, "").replace(/Z$/, "Z");
}

export function LogsView({
  initial,
  total,
  query,
}: {
  initial: LogRow[];
  total: number;
  query: LogsQuery;
}) {
  const [rows, setRows] = useState<LogRow[]>(initial);
  const [selected, setSelected] = useState<LogRow | null>(null);
  const [live, setLive] = useState(false);
  const parentRef = useRef<HTMLDivElement>(null);

  // Reset when the parent re-fetches (new filter / page change). The
  // initial array is the canonical source of truth for that page.
  useEffect(() => {
    setRows(initial);
  }, [initial]);

  // Live-tail loop. We send the filters that are currently in the URL
  // so newly-arriving logs respect them. Cursor is the newest row's
  // timestamp; prepend dedup-ed by id.
  useEffect(() => {
    if (!live) return;
    let cancelled = false;

    const tick = async () => {
      const sinceIso = rows[0]?.timestamp ?? new Date(0).toISOString();
      const res = await fetchNewerLogs({
        levels: query.levels,
        tag: query.tag,
        userId: query.userId,
        appVersion: query.appVersion,
        platform: query.platform,
        search: query.search,
        from: query.from,
        to: query.to,
        sinceIso,
        limit: 200,
      });
      if (cancelled) return;
      if (!res.ok) {
        toast.error(`Live tail: ${res.error}`);
        setLive(false);
        return;
      }
      if (res.rows.length === 0) return;
      setRows((prev) => {
        const seen = new Set(prev.map((r) => r.id));
        const fresh = res.rows.filter((r) => !seen.has(r.id));
        return [...fresh, ...prev];
      });
    };

    const id = setInterval(tick, 5000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [live, query, rows]);

  const rowVirtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 44,
    overscan: 12,
  });

  const totalPages = Math.max(1, Math.ceil(total / query.pageSize));
  const prevHref = `/logs${serializeLogsQuery(query, { page: Math.max(1, query.page - 1) })}`;
  const nextHref = `/logs${serializeLogsQuery(query, { page: Math.min(totalPages, query.page + 1) })}`;
  const prevDisabled = query.page <= 1 || live;
  const nextDisabled = query.page >= totalPages || live;

  const headerCols = useMemo(
    () =>
      [
        { key: "ts", label: "Timestamp", width: "w-44" },
        { key: "lvl", label: "Nivel", width: "w-20" },
        { key: "tag", label: "Tag", width: "w-32" },
        { key: "msg", label: "Mensaje", width: "flex-1" },
        { key: "usr", label: "Usuario", width: "w-32" },
        { key: "plt", label: "Plataforma", width: "w-24" },
      ] as const,
    [],
  );

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Switch
            id="logs-live"
            checked={live}
            onCheckedChange={setLive}
          />
          <Label htmlFor="logs-live" className="cursor-pointer">
            Live tail (5 s)
          </Label>
          {live ? (
            <span className="text-xs text-muted-foreground">
              · pausa la paginación
            </span>
          ) : null}
        </div>
        <div className="flex items-center gap-3 text-sm">
          <span className="text-muted-foreground">
            {total.toLocaleString("es-ES")} logs · página {query.page} /{" "}
            {totalPages}
          </span>
          <Button asChild size="sm" variant="outline" disabled={prevDisabled}>
            <Link href={prevHref} aria-disabled={prevDisabled}>
              ← Anterior
            </Link>
          </Button>
          <Button asChild size="sm" variant="outline" disabled={nextDisabled}>
            <Link href={nextHref} aria-disabled={nextDisabled}>
              Siguiente →
            </Link>
          </Button>
        </div>
      </div>

      <div className="rounded-lg border bg-card">
        <div className="flex border-b bg-muted/40 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {headerCols.map((c) => (
            <div key={c.key} className={`px-3 py-2 ${c.width}`}>
              {c.label}
            </div>
          ))}
        </div>
        <div ref={parentRef} className="h-[640px] overflow-auto">
          <div
            style={{
              height: rowVirtualizer.getTotalSize(),
              position: "relative",
            }}
          >
            {rowVirtualizer.getVirtualItems().map((vi) => {
              const r = rows[vi.index]!;
              return (
                <button
                  key={r.id}
                  type="button"
                  onClick={() => setSelected(r)}
                  className="absolute left-0 top-0 flex w-full items-center border-b text-left text-sm hover:bg-accent/40"
                  style={{
                    transform: `translateY(${vi.start}px)`,
                    height: vi.size,
                  }}
                >
                  <div className="w-44 px-3 font-mono text-xs text-muted-foreground">
                    {fmtTime(r.timestamp)}
                  </div>
                  <div className="w-20 px-3">
                    <Badge variant={LEVEL_BADGE[r.level]}>{r.level}</Badge>
                  </div>
                  <div className="w-32 px-3 font-mono text-xs">{r.tag}</div>
                  <div className="flex-1 truncate px-3">{r.message}</div>
                  <div className="w-32 truncate px-3 text-xs">
                    {r.user_nickname ?? r.user_id?.slice(0, 8) ?? "—"}
                  </div>
                  <div className="w-24 px-3 text-xs text-muted-foreground">
                    {r.platform}
                  </div>
                </button>
              );
            })}
            {rows.length === 0 ? (
              <div className="p-8 text-center text-sm text-muted-foreground">
                Sin logs para estos filtros.
              </div>
            ) : null}
          </div>
        </div>
      </div>

      <LogDetailSheet
        row={selected}
        onOpenChange={(open) => {
          if (!open) setSelected(null);
        }}
      />
    </div>
  );
}
```

- [ ] **Step 2: Install the missing shadcn `switch` primitive**

```bash
cd admin
pnpm dlx shadcn@latest add switch
```

- [ ] **Step 3: Commit**

```bash
git add "admin/app/(dashboard)/logs/logs-view.tsx" admin/components/ui/switch.tsx
git commit -m "feat(admin): /logs virtualized table + live tail"
```

---

## Task 9: `page.tsx` (server shell)

**Files:**
- Create: `admin/app/(dashboard)/logs/page.tsx`

- [ ] **Step 1: Write the server component**

```tsx
// admin/app/(dashboard)/logs/page.tsx
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { parseLogsQuery } from "@/lib/logs/search-params";
import { FiltersBar } from "./filters-bar";
import { LogsView } from "./logs-view";
import type { LogRow } from "./actions";

export const dynamic = "force-dynamic";

export default async function LogsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireAdmin();
  const query = parseLogsQuery(await searchParams);

  const supabase = adminClient();
  let q = supabase
    .from("admin_app_logs_view")
    .select(
      "id, timestamp, level, tag, message, error, stack_trace, context, app_version, platform, device_model, user_id, user_nickname",
      { count: "exact" },
    )
    .order("timestamp", { ascending: false });

  if (query.levels.length > 0) q = q.in("level", query.levels);
  if (query.tag) q = q.ilike("tag", `%${query.tag}%`);
  if (query.userId) q = q.eq("user_id", query.userId);
  if (query.appVersion) q = q.ilike("app_version", `%${query.appVersion}%`);
  if (query.platform) q = q.eq("platform", query.platform);
  if (query.search) q = q.ilike("message", `%${query.search}%`);
  if (query.from) q = q.gte("timestamp", `${query.from}T00:00:00.000Z`);
  if (query.to) {
    const to = new Date(`${query.to}T00:00:00.000Z`);
    to.setUTCDate(to.getUTCDate() + 1);
    q = q.lt("timestamp", to.toISOString());
  }

  const fromRow = (query.page - 1) * query.pageSize;
  const toRow = fromRow + query.pageSize - 1;
  const { data, count } = await q.range(fromRow, toRow);

  const rows = (data ?? []) as LogRow[];

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Logs</h1>
        <p className="text-sm text-muted-foreground">
          Eventos cargados por la app móvil.
        </p>
      </div>
      <FiltersBar query={query} />
      <LogsView initial={rows} total={count ?? 0} query={query} />
    </div>
  );
}
```

- [ ] **Step 2: Build verification**

```bash
cd admin
pnpm build
```

Expected: green. Routes table should include `ƒ /logs`.

- [ ] **Step 3: Commit**

```bash
git add "admin/app/(dashboard)/logs/page.tsx"
git commit -m "feat(admin): /logs server shell + build"
```

---

## Task 10: Manual E2E verification (user)

- [ ] Open `/logs`, confirm the page renders with a list of recent logs and the total count is sensible.
- [ ] Toggle the **error** level badge — only error logs remain; URL updates with `?levels=error`.
- [ ] Type in the message search box — list narrows after ~300 ms; URL updates with `?search=…`.
- [ ] Set a date range — list narrows; URL updates.
- [ ] Scroll a few thousand rows (use a low-impact filter to get more rows visible) — confirm the virtualizer keeps scroll smooth and memory steady.
- [ ] Click a row — the side panel opens with `stack_trace`, `context` JSON, and device info.
- [ ] Flip **Live tail** on. From the Flutter app emit a new error log (or insert one via SQL). Within 5 s it appears at the top.
- [ ] Confirm Prev/Next are disabled while live tail is on.
- [ ] Click "Limpiar" — URL resets, all filters cleared.

---

## Self-Review

**Spec coverage:**
- ✅ Filter by level / tag / user_id / app_version / platform / date range / message search → Task 6
- ✅ Virtualized table (TanStack Virtual) → Task 8
- ✅ Side panel with stack/context/device_model → Task 7
- ✅ Live tail polling every 5 s → Task 8
- ✅ Server-side pagination using existing indexes → Task 9

**Placeholder scan:** none.

**Type consistency:** `LogRow` is defined in `actions.ts` and re-imported by `logs-view.tsx` and `log-detail-sheet.tsx`. `LogsQuery` flows from `search-params.ts` → `page.tsx` → `filters-bar.tsx` / `logs-view.tsx` consistently.
