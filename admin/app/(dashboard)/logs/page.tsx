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
