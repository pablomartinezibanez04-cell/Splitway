// admin/app/(dashboard)/routes/routes-table.tsx
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
  parseRoutesQuery,
  serializeRoutesQuery,
  type SortKey,
} from "@/lib/routes/search-params";

type Row = {
  id: string | null;
  name: string | null;
  owner_nickname: string | null;
  difficulty: string | null;
  location_label: string | null;
  thumbnail_url: string | null;
  is_official: boolean | null;
  created_at: string | null;
  sectors_count: number | null;
  sessions_count: number | null;
};

// Timezone-stable date formatter. Parsing an ISO timestamp with `new Date()`
// and formatting it gives different results on the server (UTC) vs the
// browser (local TZ), which causes hydration mismatches. We slice the
// YYYY-MM-DD prefix from the raw string instead — same characters on both
// sides regardless of timezone.
function fmt(date: string | null): string {
  if (!date) return "—";
  const ymd = date.slice(0, 10);
  const parts = ymd.split("-");
  if (parts.length !== 3) return "—";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

export function RoutesTable({ rows }: { rows: Row[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseRoutesQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: SortKey) {
    const dir =
      query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeRoutesQuery(query, { sort: key, dir }));
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
      id: "thumbnail",
      header: "",
      cell: ({ row }) => (
        <div className="h-10 w-16 overflow-hidden rounded bg-muted">
          {row.original.thumbnail_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={row.original.thumbnail_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "name",
      header: () => <SortableHead label="Nombre" sortKey="name" />,
      cell: ({ row }) => (
        <div className="flex items-center gap-2">
          <span className="font-medium">{row.original.name || "—"}</span>
          {row.original.is_official ? (
            <Badge variant="default" className="text-xs">
              Oficial
            </Badge>
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "owner_nickname",
      header: "Propietario",
      cell: ({ row }) => row.original.owner_nickname ?? "—",
    },
    {
      accessorKey: "difficulty",
      header: () => <SortableHead label="Dificultad" sortKey="difficulty" />,
      cell: ({ row }) => (
        <Badge variant="outline">{row.original.difficulty ?? "—"}</Badge>
      ),
    },
    {
      accessorKey: "sectors_count",
      header: () => <SortableHead label="Sectores" sortKey="sectors_count" />,
      cell: ({ row }) => row.original.sectors_count ?? 0,
    },
    {
      accessorKey: "sessions_count",
      header: () => (
        <SortableHead label="Sesiones" sortKey="sessions_count" />
      ),
      cell: ({ row }) => row.original.sessions_count ?? 0,
    },
    {
      accessorKey: "location_label",
      header: "Ubicación",
      cell: ({ row }) => row.original.location_label ?? "—",
    },
    {
      accessorKey: "created_at",
      header: () => <SortableHead label="Creada" sortKey="created_at" />,
      cell: ({ row }) => fmt(row.original.created_at),
    },
  ];

  const table = useReactTable({
    data: rows,
    columns,
    getCoreRowModel: getCoreRowModel(),
  });

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
                    : flexRender(h.column.columnDef.header, h.getContext())}
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
                onClick={() => {
                  if (row.original.id) {
                    router.push(`/routes/${row.original.id}`);
                  }
                }}
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
