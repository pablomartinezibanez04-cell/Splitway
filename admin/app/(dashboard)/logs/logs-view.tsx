// admin/app/(dashboard)/logs/logs-view.tsx
"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useVirtualizer } from "@tanstack/react-virtual";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  type LogsQuery,
  serializeLogsQuery,
} from "@/lib/logs/search-params";
import { fetchNewerLogs, type LogRow } from "./actions";
import { LogDetailSheet } from "./log-detail-sheet";

const LEVEL_BADGE: Record<
  LogRow["level"],
  "default" | "secondary" | "destructive" | "outline"
> = {
  debug: "outline",
  info: "secondary",
  warning: "default",
  error: "destructive",
};

function fmtTime(iso: string): string {
  // Trim sub-second precision and Z suffix for compact display.
  // Hydration-stable: pure string slicing, no timezone math.
  return iso.replace("T", " ").replace(/\.\d+/, "").replace(/Z$/, "Z");
}

export function LogsView({
  initial,
  total,
  query,
}: {
  initial: LogRow[];
  total: number;
  query: LogsQuery;
}) {
  const [rows, setRows] = useState<LogRow[]>(initial);
  const [selected, setSelected] = useState<LogRow | null>(null);
  const [live, setLive] = useState(false);
  const parentRef = useRef<HTMLDivElement>(null);

  // Reset when the parent re-fetches (new filter / page change). The
  // initial array is the canonical source of truth for that page.
  useEffect(() => {
    setRows(initial);
  }, [initial]);

  // Live-tail loop. We send the filters that are currently in the URL
  // so newly-arriving logs respect them. Cursor is the newest row's
  // timestamp; prepend dedup-ed by id.
  useEffect(() => {
    if (!live) return;
    let cancelled = false;

    const tick = async () => {
      const sinceIso = rows[0]?.timestamp ?? new Date(0).toISOString();
      const res = await fetchNewerLogs({
        levels: query.levels,
        tag: query.tag,
        userId: query.userId,
        appVersion: query.appVersion,
        platform: query.platform,
        search: query.search,
        from: query.from,
        to: query.to,
        sinceIso,
        limit: 200,
      });
      if (cancelled) return;
      if (!res.ok) {
        toast.error(`Live tail: ${res.error}`);
        setLive(false);
        return;
      }
      if (res.rows.length === 0) return;
      setRows((prev) => {
        const seen = new Set(prev.map((r) => r.id));
        const fresh = res.rows.filter((r) => !seen.has(r.id));
        return [...fresh, ...prev];
      });
    };

    const id = setInterval(tick, 5000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [live, query, rows]);

  const rowVirtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 44,
    overscan: 12,
  });

  const totalPages = Math.max(1, Math.ceil(total / query.pageSize));
  const prevHref = `/logs${serializeLogsQuery(query, { page: Math.max(1, query.page - 1) })}`;
  const nextHref = `/logs${serializeLogsQuery(query, { page: Math.min(totalPages, query.page + 1) })}`;
  const prevDisabled = query.page <= 1 || live;
  const nextDisabled = query.page >= totalPages || live;

  const headerCols = useMemo(
    () =>
      [
        { key: "ts", label: "Timestamp", width: "w-44" },
        { key: "lvl", label: "Nivel", width: "w-20" },
        { key: "tag", label: "Tag", width: "w-32" },
        { key: "msg", label: "Mensaje", width: "flex-1" },
        { key: "usr", label: "Usuario", width: "w-32" },
        { key: "plt", label: "Plataforma", width: "w-24" },
      ] as const,
    [],
  );

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Switch
            id="logs-live"
            checked={live}
            onCheckedChange={setLive}
          />
          <Label htmlFor="logs-live" className="cursor-pointer">
            Live tail (5 s)
          </Label>
          {live ? (
            <span className="text-xs text-muted-foreground">
              · pausa la paginación
            </span>
          ) : null}
        </div>
        <div className="flex items-center gap-3 text-sm">
          <span className="text-muted-foreground">
            {total.toLocaleString("es-ES")} logs · página {query.page} /{" "}
            {totalPages}
          </span>
          <Button asChild size="sm" variant="outline" disabled={prevDisabled}>
            <Link href={prevHref} aria-disabled={prevDisabled}>
              ← Anterior
            </Link>
          </Button>
          <Button asChild size="sm" variant="outline" disabled={nextDisabled}>
            <Link href={nextHref} aria-disabled={nextDisabled}>
              Siguiente →
            </Link>
          </Button>
        </div>
      </div>

      <div className="rounded-lg border bg-card">
        <div className="flex border-b bg-muted/40 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {headerCols.map((c) => (
            <div key={c.key} className={`px-3 py-2 ${c.width}`}>
              {c.label}
            </div>
          ))}
        </div>
        <div ref={parentRef} className="h-[640px] overflow-auto">
          <div
            style={{
              height: rowVirtualizer.getTotalSize(),
              position: "relative",
            }}
          >
            {rowVirtualizer.getVirtualItems().map((vi) => {
              const r = rows[vi.index]!;
              return (
                <button
                  key={r.id}
                  type="button"
                  onClick={() => setSelected(r)}
                  className="absolute left-0 top-0 flex w-full items-center border-b text-left text-sm hover:bg-accent/40"
                  style={{
                    transform: `translateY(${vi.start}px)`,
                    height: vi.size,
                  }}
                >
                  <div className="w-44 px-3 font-mono text-xs text-muted-foreground">
                    {fmtTime(r.timestamp)}
                  </div>
                  <div className="w-20 px-3">
                    <Badge variant={LEVEL_BADGE[r.level]}>{r.level}</Badge>
                  </div>
                  <div className="w-32 px-3 font-mono text-xs">{r.tag}</div>
                  <div className="flex-1 truncate px-3">{r.message}</div>
                  <div className="w-32 truncate px-3 text-xs">
                    {r.user_nickname ?? r.user_id?.slice(0, 8) ?? "—"}
                  </div>
                  <div className="w-24 px-3 text-xs text-muted-foreground">
                    {r.platform}
                  </div>
                </button>
              );
            })}
            {rows.length === 0 ? (
              <div className="p-8 text-center text-sm text-muted-foreground">
                Sin logs para estos filtros.
              </div>
            ) : null}
          </div>
        </div>
      </div>

      <LogDetailSheet
        row={selected}
        onOpenChange={(open) => {
          if (!open) setSelected(null);
        }}
      />
    </div>
  );
}
