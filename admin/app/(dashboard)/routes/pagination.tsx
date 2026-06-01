// admin/app/(dashboard)/routes/pagination.tsx
"use client";

import { usePathname, useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  serializeRoutesQuery,
  type RoutesQuery,
} from "@/lib/routes/search-params";

export function Pagination({
  query,
  total,
}: {
  query: RoutesQuery;
  total: number;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const totalPages = Math.max(1, Math.ceil(total / query.pageSize));

  function go(page: number) {
    router.push(pathname + serializeRoutesQuery(query, { page }));
  }

  return (
    <div className="flex items-center justify-between text-sm text-muted-foreground">
      <div>
        Página {query.page} de {totalPages}
      </div>
      <div className="flex items-center gap-2">
        <Select
          value={String(query.pageSize)}
          onValueChange={(v) =>
            router.push(
              pathname +
                serializeRoutesQuery(query, {
                  pageSize: Number(v) as 25 | 50 | 100,
                  page: 1,
                }),
            )
          }
        >
          <SelectTrigger className="h-8 w-20">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="25">25</SelectItem>
            <SelectItem value="50">50</SelectItem>
            <SelectItem value="100">100</SelectItem>
          </SelectContent>
        </Select>
        <Button
          variant="outline"
          size="sm"
          disabled={query.page <= 1}
          onClick={() => go(query.page - 1)}
        >
          Anterior
        </Button>
        <Button
          variant="outline"
          size="sm"
          disabled={query.page >= totalPages}
          onClick={() => go(query.page + 1)}
        >
          Siguiente
        </Button>
      </div>
    </div>
  );
}
