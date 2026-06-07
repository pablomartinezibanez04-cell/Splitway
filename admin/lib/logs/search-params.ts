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
