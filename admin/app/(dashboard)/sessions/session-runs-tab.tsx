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
