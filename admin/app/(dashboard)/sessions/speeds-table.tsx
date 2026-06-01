// admin/app/(dashboard)/sessions/speeds-table.tsx
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
  parseSessionsQuery,
  serializeSessionsQuery,
  type SpeedsSortKey,
} from "@/lib/sessions/search-params";

type Row = {
  id: string | null;
  owner_nickname: string | null;
  vehicle_name: string | null;
  name: string | null;
  selected_metrics: string[] | null;
  is_partial: boolean | null;
  started_at: string | null;
  created_at: string | null;
};

function fmtDate(s: string | null): string {
  if (!s) return "—";
  const ymd = s.slice(0, 10);
  const parts = ymd.split("-");
  if (parts.length !== 3) return "—";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

export function SpeedsTable({ rows }: { rows: Row[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseSessionsQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: SpeedsSortKey) {
    const dir = query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeSessionsQuery(query, { sort: key, dir }));
  }

  function SortableHead({
    label,
    sortKey,
  }: {
    label: string;
    sortKey: SpeedsSortKey;
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
      accessorKey: "owner_nickname",
      header: "Usuario",
      cell: ({ row }) => row.original.owner_nickname ?? "—",
    },
    {
      accessorKey: "vehicle_name",
      header: "Vehículo",
      cell: ({ row }) => row.original.vehicle_name ?? "—",
    },
    {
      accessorKey: "name",
      header: () => <SortableHead label="Nombre" sortKey="name" />,
      cell: ({ row }) => row.original.name ?? "—",
    },
    {
      id: "metrics",
      header: "Métricas",
      cell: ({ row }) => (
        <div className="flex flex-wrap gap-1">
          {(row.original.selected_metrics ?? []).slice(0, 4).map((m) => (
            <Badge key={m} variant="outline" className="text-xs">
              {m}
            </Badge>
          ))}
          {(row.original.selected_metrics?.length ?? 0) > 4 ? (
            <span className="text-xs text-muted-foreground">
              +{(row.original.selected_metrics!.length - 4)}
            </span>
          ) : null}
        </div>
      ),
    },
    {
      accessorKey: "created_at",
      header: () => <SortableHead label="Creada" sortKey="created_at" />,
      cell: ({ row }) => fmtDate(row.original.created_at),
    },
    {
      accessorKey: "is_partial",
      header: () => <SortableHead label="Parcial" sortKey="is_partial" />,
      cell: ({ row }) =>
        row.original.is_partial ? (
          <Badge variant="secondary">Parcial</Badge>
        ) : (
          <Badge variant="outline">Completa</Badge>
        ),
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
          {rows.length === 0 ? (
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
                    router.push(`/sessions/speed-sessions/${row.original.id}`);
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
