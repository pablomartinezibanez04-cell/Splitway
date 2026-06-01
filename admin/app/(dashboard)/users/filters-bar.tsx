// admin/app/(dashboard)/users/filters-bar.tsx
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
  type RoleFilter,
  type StatusFilter,
  serializeUsersQuery,
  type UsersQuery,
} from "@/lib/users/search-params";

export function FiltersBar({ query }: { query: UsersQuery }) {
  const router = useRouter();
  const pathname = usePathname();
  const [, startTransition] = useTransition();
  const [search, setSearch] = useState(query.search);

  // Debounce the search input by 300ms before pushing to URL.
  useEffect(() => {
    if (search === query.search) return;
    const id = setTimeout(() => {
      startTransition(() => {
        router.push(
          pathname + serializeUsersQuery(query, { search, page: 1 }),
        );
      });
    }, 300);
    return () => clearTimeout(id);
  }, [search, query, router, pathname]);

  function pushOverride(o: Partial<UsersQuery>) {
    startTransition(() => {
      router.push(pathname + serializeUsersQuery(query, { ...o, page: 1 }));
    });
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Input
        placeholder="Buscar por email o apodo…"
        className="max-w-sm"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      <Select
        value={query.role}
        onValueChange={(v) => pushOverride({ role: v as RoleFilter })}
      >
        <SelectTrigger className="w-40">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todos los roles</SelectItem>
          <SelectItem value="user">user</SelectItem>
          <SelectItem value="admin">admin</SelectItem>
          <SelectItem value="superadmin">superadmin</SelectItem>
        </SelectContent>
      </Select>
      <Select
        value={query.status}
        onValueChange={(v) => pushOverride({ status: v as StatusFilter })}
      >
        <SelectTrigger className="w-36">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">Todos</SelectItem>
          <SelectItem value="active">Activos</SelectItem>
          <SelectItem value="banned">Baneados</SelectItem>
        </SelectContent>
      </Select>
    </div>
  );
}
