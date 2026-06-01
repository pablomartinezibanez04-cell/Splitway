// admin/lib/users/search-params.ts

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
