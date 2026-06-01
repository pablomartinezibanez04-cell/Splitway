// admin/app/(dashboard)/routes/filters-bar.tsx
"use client";

import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, useTransition } from "react";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  type DifficultyFilter,
  type OfficialFilter,
  serializeRoutesQuery,
  type RoutesQuery,
} from "@/lib/routes/search-params";

export function FiltersBar({ query }: { query: RoutesQuery }) {
  const router = useRouter();
  const pathname = usePathname();
  const [, startTransition] = useTransition();
  const [search, setSearch] = useState(query.search);

  useEffect(() => {
    if (search === query.search) return;
    const id = setTimeout(() => {
      startTransition(() => {
        router.push(
          pathname + serializeRoutesQuery(query, { search, page: 1 }),
        );
      });
    }, 300);
    return () => clearTimeout(id);
  }, [search, query, router, pathname]);

  function pushOverride(o: Partial<RoutesQuery>) {
    startTransition(() => {
      router.push(pathname + serializeRoutesQuery(query, { ...o, page: 1 }));
    });
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Input
        placeholder="Buscar por nombre, propietario, email o ubicación…"
        className="max-w-sm"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      <Select
        value={query.difficulty}
        onValueChange={(v) =>
          pushOverride({ difficulty: v as DifficultyFilter })
        }
      >
        <SelectTrigger className="w-40">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todas las dificultades</SelectItem>
          <SelectItem value="easy">easy</SelectItem>
          <SelectItem value="medium">medium</SelectItem>
          <SelectItem value="hard">hard</SelectItem>
          <SelectItem value="extreme">extreme</SelectItem>
        </SelectContent>
      </Select>
      <Select
        value={query.official}
        onValueChange={(v) => pushOverride({ official: v as OfficialFilter })}
      >
        <SelectTrigger className="w-36">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todas</SelectItem>
          <SelectItem value="official">Oficiales</SelectItem>
          <SelectItem value="community">Comunidad</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}
