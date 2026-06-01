// admin/app/(dashboard)/users/users-table.tsx
"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import {
  useReactTable,
  getCoreRowModel,
  flexRender,
  type ColumnDef,
} from "@tanstack/react-table";
import { ArrowUpDown } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  parseUsersQuery,
  serializeUsersQuery,
  type SortKey,
} from "@/lib/users/search-params";

type Row = {
  id: string | null;
  nickname: string | null;
  avatar_url: string | null;
  role: string | null;
  email: string | null;
  signup_date: string | null;
  banned_until: string | null;
  last_activity: string | null;
  sessions_count: number | null;
  routes_count: number | null;
};

// Timezone-stable date formatter. Parsing an ISO timestamp with `new Date()`
// and formatting it gives different results on the server (UTC) vs the
// browser (local TZ), which causes hydration mismatches. We slice the
// YYYY-MM-DD prefix from the raw string instead — same characters on both
// sides regardless of timezone. The view returns 'epoch' (1970-01-01) for
// "no activity" rows; those still get filtered out as "—".
function fmt(date: string | null): string {
  if (!date) return "—";
  const ymd = date.slice(0, 10);
  if (ymd < "2000-01-01") return "—";
  const parts = ymd.split("-");
  if (parts.length !== 3) return "—";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

function statusOf(row: Row): "active" | "banned" {
  if (!row.banned_until) return "active";
  return new Date(row.banned_until) > new Date() ? "banned" : "active";
}

export function UsersTable({
  rows,
  currentAdminRole,
}: {
  rows: Row[];
  currentAdminRole: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseUsersQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: SortKey) {
    const dir =
      query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeUsersQuery(query, { sort: key, dir }));
  }

  function SortableHead({
    label,
    sortKey,
  }: {
    label: string;
    sortKey: SortKey;
  }) {
    const active = query.sort === sortKey;
    return (
      <Button
        variant="ghost"
        size="sm"
        className="-ml-3 h-7 px-2"
        onClick={() => toggleSort(sortKey)}
      >
        {label}
        <ArrowUpDown
          className={
            "ml-1 h-3 w-3 " +
            (active ? "text-foreground" : "text-muted-foreground")
          }
        />
      </Button>
    );
  }

  const columns: ColumnDef<Row>[] = [
    {
      id: "avatar",
      header: "",
      cell: ({ row }) => (
        <div className="h-8 w-8 overflow-hidden rounded-full bg-muted">
          {row.original.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.original.avatar_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "nickname",
      header: () => <SortableHead label="Nickname" sortKey="nickname" />,
      cell: ({ row }) => (
        <span className="font-medium">{row.original.nickname || "—"}</span>
      ),
    },
    {
      accessorKey: "email",
      header: "Email",
      cell: ({ row }) => row.original.email ?? "—",
    },
    {
      accessorKey: "role",
      header: "Rol",
      cell: ({ row }) => (
        <Badge
          variant={
            row.original.role === "superadmin"
              ? "default"
              : row.original.role === "admin"
                ? "secondary"
                : "outline"
          }
        >
          {row.original.role ?? "user"}
        </Badge>
      ),
    },
    {
      accessorKey: "signup_date",
      header: () => <SortableHead label="Alta" sortKey="signup_date" />,
      cell: ({ row }) => fmt(row.original.signup_date),
    },
    {
      accessorKey: "last_activity",
      header: () => (
        <SortableHead label="Última actividad" sortKey="last_activity" />
      ),
      cell: ({ row }) => fmt(row.original.last_activity),
    },
    {
      accessorKey: "sessions_count",
      header: () => <SortableHead label="Sesiones" sortKey="sessions_count" />,
      cell: ({ row }) => row.original.sessions_count ?? 0,
    },
    {
      accessorKey: "routes_count",
      header: () => <SortableHead label="Rutas" sortKey="routes_count" />,
      cell: ({ row }) => row.original.routes_count ?? 0,
    },
    {
      id: "status",
      header: "Estado",
      cell: ({ row }) => {
        const s = statusOf(row.original);
        return (
          <Badge variant={s === "banned" ? "destructive" : "outline"}>
            {s === "banned" ? "Baneado" : "Activo"}
          </Badge>
        );
      },
    },
  ];

  const table = useReactTable({
    data: rows,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

  // currentAdminRole reserved for future role-aware UI (admin vs superadmin
  // sees the same list for now).
  void currentAdminRole;

  return (
    <div className="rounded-md border">
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((g) => (
            <TableRow key={g.id}>
              {g.headers.map((h) => (
                <TableHead key={h.id}>
                  {h.isPlaceholder
                    ? null
                    : flexRender(
                        h.column.columnDef.header,
                        h.getContext(),
                      )}
                </TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {table.getRowModel().rows.length === 0 ? (
            <TableRow>
              <TableCell
                colSpan={columns.length}
                className="text-center text-sm text-muted-foreground"
              >
                Sin resultados.
              </TableCell>
            </TableRow>
          ) : (
            table.getRowModel().rows.map((row) => (
              <TableRow
                key={row.id}
                className="cursor-pointer hover:bg-accent/40"
                onClick={() => row.original.id && router.push(`/users/${row.original.id}`)}
              >
                {row.getVisibleCells().map((cell) => (
                  <TableCell key={cell.id}>
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </TableCell>
                ))}
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </div>
  );
}
