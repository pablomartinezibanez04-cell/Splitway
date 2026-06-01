// admin/app/(dashboard)/sessions/runs-table.tsx
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
  type RunsSortKey,
} from "@/lib/sessions/search-params";

type Row = {
  id: string | null;
  owner_nickname: string | null;
  vehicle_name: string | null;
  route_name: string | null;
  started_at: string | null;
  ended_at: string | null;
  status: string | null;
  duration_seconds: number | null;
  total_distance_m: number | null;
  avg_speed_mps: number | null;
  max_speed_mps: number | null;
};

function fmtDate(s: string | null): string {
  if (!s) return "—";
  const ymd = s.slice(0, 10);
  const parts = ymd.split("-");
  if (parts.length !== 3) return "—";
  return `${parts[2]}/${parts[1]}/${parts[0]}`;
}

function fmtDuration(seconds: number | null): string {
  if (seconds == null || seconds <= 0) return "—";
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}m ${String(s).padStart(2, "0")}s`;
}

function fmtSpeed(mps: number | null): string {
  if (mps == null) return "—";
  return `${(mps * 3.6).toFixed(1)} km/h`;
}

export function RunsTable({ rows }: { rows: Row[] }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseSessionsQuery(Object.fromEntries(searchParams.entries()));

  function toggleSort(key: RunsSortKey) {
    const dir = query.sort === key && query.dir === "desc" ? "asc" : "desc";
    router.push(pathname + serializeSessionsQuery(query, { sort: key, dir }));
  }

  function SortableHead({
    label,
    sortKey,
  }: {
    label: string;
    sortKey: RunsSortKey;
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
      accessorKey: "route_name",
      header: "Ruta",
      cell: ({ row }) => row.original.route_name ?? "—",
    },
    {
      accessorKey: "started_at",
      header: () => <SortableHead label="Fecha" sortKey="started_at" />,
      cell: ({ row }) => fmtDate(row.original.started_at),
    },
    {
      accessorKey: "duration_seconds",
      header: () => <SortableHead label="Duración" sortKey="duration_seconds" />,
      cell: ({ row }) => fmtDuration(row.original.duration_seconds),
    },
    {
      accessorKey: "total_distance_m",
      header: () => (
        <SortableHead label="Distancia (m)" sortKey="total_distance_m" />
      ),
      cell: ({ row }) =>
        row.original.total_distance_m != null
          ? Math.round(row.original.total_distance_m).toLocaleString("es-ES")
          : "—",
    },
    {
      accessorKey: "avg_speed_mps",
      header: () => (
        <SortableHead label="Vel. media" sortKey="avg_speed_mps" />
      ),
      cell: ({ row }) => fmtSpeed(row.original.avg_speed_mps),
    },
    {
      accessorKey: "max_speed_mps",
      header: () => <SortableHead label="Vel. máx" sortKey="max_speed_mps" />,
      cell: ({ row }) => fmtSpeed(row.original.max_speed_mps),
    },
    {
      accessorKey: "status",
      header: "Estado",
      cell: ({ row }) => (
        <Badge variant="outline">{row.original.status ?? "—"}</Badge>
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
                    router.push(`/sessions/runs/${row.original.id}`);
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
