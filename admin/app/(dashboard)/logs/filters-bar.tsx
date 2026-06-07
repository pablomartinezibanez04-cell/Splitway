// admin/app/(dashboard)/logs/filters-bar.tsx
"use client";

import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  type LogLevel,
  type LogsQuery,
  serializeLogsQuery,
} from "@/lib/logs/search-params";

const LEVELS: LogLevel[] = ["debug", "info", "warning", "error"];

export function FiltersBar({ query }: { query: LogsQuery }) {
  const router = useRouter();
  const [search, setSearch] = useState(query.search);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Debounced free-text search.
  useEffect(() => {
    if (search === query.search) return;
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      router.push(`/logs${serializeLogsQuery(query, { search, page: 1 })}`);
    }, 300);
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  function toggleLevel(level: LogLevel) {
    const next = query.levels.includes(level)
      ? query.levels.filter((l) => l !== level)
      : [...query.levels, level];
    router.push(`/logs${serializeLogsQuery(query, { levels: next, page: 1 })}`);
  }

  function setField(key: keyof LogsQuery, value: string) {
    router.push(
      `/logs${serializeLogsQuery(query, { [key]: value, page: 1 } as Partial<LogsQuery>)}`,
    );
  }

  return (
    <div className="space-y-3 rounded-lg border bg-card p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm text-muted-foreground">Niveles:</span>
        {LEVELS.map((l) => {
          const active = query.levels.includes(l);
          return (
            <Badge
              key={l}
              variant={active ? "default" : "outline"}
              className="cursor-pointer select-none"
              onClick={() => toggleLevel(l)}
            >
              {l}
            </Badge>
          );
        })}
      </div>

      <div className="grid gap-3 md:grid-cols-3 lg:grid-cols-4">
        <div className="space-y-1">
          <Label htmlFor="logs-search">Mensaje</Label>
          <Input
            id="logs-search"
            placeholder="Buscar…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-tag">Tag</Label>
          <Input
            id="logs-tag"
            placeholder="auth, route_editor…"
            defaultValue={query.tag}
            onBlur={(e) => {
              const v = e.target.value.trim();
              if (v !== query.tag) setField("tag", v);
            }}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-user">User ID</Label>
          <Input
            id="logs-user"
            placeholder="UUID…"
            defaultValue={query.userId}
            onBlur={(e) => {
              const v = e.target.value.trim();
              if (v !== query.userId) setField("userId", v);
            }}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-version">App version</Label>
          <Input
            id="logs-version"
            placeholder="1.2.3"
            defaultValue={query.appVersion}
            onBlur={(e) => {
              const v = e.target.value.trim();
              if (v !== query.appVersion) setField("appVersion", v);
            }}
          />
        </div>
        <div className="space-y-1">
          <Label>Plataforma</Label>
          <Select
            value={query.platform || "all"}
            onValueChange={(v) => setField("platform", v === "all" ? "" : v)}
          >
            <SelectTrigger>
              <SelectValue placeholder="Todas" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todas</SelectItem>
              <SelectItem value="ios">iOS</SelectItem>
              <SelectItem value="android">Android</SelectItem>
              <SelectItem value="web">Web</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-from">Desde</Label>
          <Input
            id="logs-from"
            type="date"
            defaultValue={query.from}
            onChange={(e) => setField("from", e.target.value)}
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="logs-to">Hasta</Label>
          <Input
            id="logs-to"
            type="date"
            defaultValue={query.to}
            onChange={(e) => setField("to", e.target.value)}
          />
        </div>
        <div className="flex items-end">
          <Button
            type="button"
            variant="ghost"
            onClick={() => router.push("/logs")}
          >
            Limpiar
          </Button>
        </div>
      </div>
    </div>
  );
}
