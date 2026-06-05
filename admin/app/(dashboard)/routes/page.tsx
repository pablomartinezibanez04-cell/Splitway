// admin/app/(dashboard)/routes/page.tsx
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { parseRoutesQuery } from "@/lib/routes/search-params";
import { FiltersBar } from "./filters-bar";
import { RoutesTable } from "./routes-table";
import { Pagination } from "./pagination";

export const dynamic = "force-dynamic";

export default async function RoutesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  await requireAdmin();
  const q = parseRoutesQuery(await searchParams);
  const supabase = adminClient();

  let query = supabase
    .from("admin_routes_view")
    .select("*", { count: "exact" });

  if (q.search.trim() !== "") {
    const term = `%${q.search.trim()}%`;
    query = query.or(
      `name.ilike.${term},owner_nickname.ilike.${term},owner_email.ilike.${term},location_label.ilike.${term}`,
    );
  }
  if (q.difficulty !== "all") {
    query = query.eq("difficulty", q.difficulty);
  }
  if (q.official === "official") {
    query = query.eq("is_official", true);
  }
  if (q.official === "community") {
    query = query.eq("is_official", false);
  }

  query = query.order(q.sort, { ascending: q.dir === "asc" });
  const from = (q.page - 1) * q.pageSize;
  const to = from + q.pageSize - 1;
  query = query.range(from, to);

  const { data: rows, count, error } = await query;
  if (error) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold">Rutas</h1>
        <p className="text-sm text-destructive">
          Error al cargar la lista: {error.message}
        </p>
      </div>
    );
  }

  const total = count ?? 0;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Rutas</h1>
        <p className="text-sm text-muted-foreground">
          {total} {total === 1 ? "ruta" : "rutas"} en total.
        </p>
      </div>
      <FiltersBar query={q} />
      <RoutesTable rows={rows ?? []} />
      <Pagination query={q} total={total} />
    </div>
  );
}
