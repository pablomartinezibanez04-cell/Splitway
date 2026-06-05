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
