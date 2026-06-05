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
