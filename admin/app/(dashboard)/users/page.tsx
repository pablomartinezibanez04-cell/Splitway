// admin/app/(dashboard)/users/page.tsx
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { parseUsersQuery } from "@/lib/users/search-params";
import { FiltersBar } from "./filters-bar";
import { UsersTable } from "./users-table";
import { Pagination } from "./pagination";

export const dynamic = "force-dynamic";

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const admin = await requireAdmin();
  const q = parseUsersQuery(await searchParams);
  const supabase = adminClient();

  let query = supabase
    .from("admin_users_view")
    .select("*", { count: "exact" });

  if (q.search.trim() !== "") {
    const term = `%${q.search.trim()}%`;
    query = query.or(`email.ilike.${term},nickname.ilike.${term}`);
  }
  if (q.role !== "all") {
    query = query.eq("role", q.role);
  }
  if (q.status === "active") {
    query = query.or("banned_until.is.null,banned_until.lt.now()");
  }
  if (q.status === "banned") {
    query = query.gt("banned_until", new Date().toISOString());
  }

  query = query.order(q.sort, { ascending: q.dir === "asc" });
  const from = (q.page - 1) * q.pageSize;
  const to = from + q.pageSize - 1;
  query = query.range(from, to);

  const { data: rows, count, error } = await query;
  if (error) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-semibold">Usuarios</h1>
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
        <h1 className="text-2xl font-semibold">Usuarios</h1>
        <p className="text-sm text-muted-foreground">
          {total} {total === 1 ? "usuario" : "usuarios"} en total.
        </p>
      </div>
      <FiltersBar query={q} />
      <UsersTable rows={rows ?? []} currentAdminRole={admin.role} />
      <Pagination query={q} total={total} />
    </div>
  );
}
