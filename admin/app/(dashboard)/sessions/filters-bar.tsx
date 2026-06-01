// admin/app/(dashboard)/sessions/filters-bar.tsx
"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, useTransition } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  serializeSessionsQuery,
  type SessionsQuery,
} from "@/lib/sessions/search-params";

export function FiltersBar({ query }: { query: SessionsQuery }) {
  const router = useRouter();
  const pathname = usePathname();
  const [, startTransition] = useTransition();
  const [search, setSearch] = useState(query.search);

  useEffect(() => {
    if (search === query.search) return;
    const id = setTimeout(() => {
      startTransition(() => {
        router.push(
          pathname + serializeSessionsQuery(query, { search, page: 1 }),
        );
      });
    }, 300);
    return () => clearTimeout(id);
  }, [search, query, router, pathname]);

  function pushDate(field: "from" | "to", value: string) {
    startTransition(() => {
      router.push(
        pathname +
          serializeSessionsQuery(query, { [field]: value, page: 1 } as Partial<SessionsQuery>),
      );
    });
  }

  return (
    <div className="flex flex-wrap items-end gap-3">
      <div className="flex-1 min-w-[220px] space-y-1">
        <Label htmlFor="sessions-search">Buscar</Label>
        <Input
          id="sessions-search"
          placeholder="usuario o vehículo…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>
      <div className="space-y-1">
        <Label htmlFor="sessions-from">Desde</Label>
        <Input
          id="sessions-from"
          type="date"
          value={query.from}
          onChange={(e) => pushDate("from", e.target.value)}
          className="w-44"
        />
      </div>
      <div className="space-y-1">
        <Label htmlFor="sessions-to">Hasta</Label>
        <Input
          id="sessions-to"
          type="date"
          value={query.to}
          onChange={(e) => pushDate("to", e.target.value)}
          className="w-44"
        />
      </div>
    </div>
  );
}
