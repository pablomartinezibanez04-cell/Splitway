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
