// admin/app/(dashboard)/sessions/tabs-switcher.tsx
"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  parseSessionsQuery,
  serializeSessionsQuery,
  type SessionTab,
} from "@/lib/sessions/search-params";

export function TabsSwitcher() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const query = parseSessionsQuery(Object.fromEntries(searchParams.entries()));

  function go(tab: SessionTab) {
    // Switching tab resets pagination + sort to that tab's defaults.
    router.push(
      pathname +
        serializeSessionsQuery(query, {
          tab,
          page: 1,
          sort:
            tab === "speed-sessions"
              ? "created_at"
              : "started_at",
        }),
    );
  }

  return (
    <Tabs value={query.tab} onValueChange={(v) => go(v as SessionTab)}>
      <TabsList>
        <TabsTrigger value="runs">Cronos</TabsTrigger>
        <TabsTrigger value="free-rides">Libres</TabsTrigger>
        <TabsTrigger value="speed-sessions">Velocidad</TabsTrigger>
      </TabsList>
    </Tabs>
  );
}
