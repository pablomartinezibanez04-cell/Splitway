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
