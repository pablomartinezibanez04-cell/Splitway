// admin/app/(dashboard)/logs/log-detail-sheet.tsx
"use client";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { Badge } from "@/components/ui/badge";
import type { LogRow } from "./actions";

const LEVEL_VARIANT: Record<
  LogRow["level"],
  "default" | "secondary" | "destructive" | "outline"
> = {
  debug: "outline",
  info: "secondary",
  warning: "default",
  error: "destructive",
};

export function LogDetailSheet({
  row,
  onOpenChange,
}: {
  row: LogRow | null;
  onOpenChange: (open: boolean) => void;
}) {
  return (
    <Sheet open={row != null} onOpenChange={onOpenChange}>
      <SheetContent className="w-full max-w-2xl overflow-y-auto sm:max-w-2xl">
        {row ? (
          <>
            <SheetHeader>
              <SheetTitle className="flex flex-wrap items-center gap-2">
                <Badge variant={LEVEL_VARIANT[row.level]}>{row.level}</Badge>
                <span className="font-mono text-xs text-muted-foreground">
                  {row.tag}
                </span>
              </SheetTitle>
              <SheetDescription className="text-foreground">
                {row.message}
              </SheetDescription>
            </SheetHeader>

            <div className="mt-6 space-y-6 text-sm">
              <Section label="Timestamp">
                <code className="font-mono">{row.timestamp}</code>
              </Section>
              <Section label="Usuario">
                {row.user_nickname ? (
                  <>
                    <span className="font-medium">{row.user_nickname}</span>{" "}
                    <span className="text-xs text-muted-foreground">
                      ({row.user_id ?? "—"})
                    </span>
                  </>
                ) : row.user_id ? (
                  <code className="font-mono text-xs">{row.user_id}</code>
                ) : (
                  <span className="text-muted-foreground">anónimo</span>
                )}
              </Section>
              <Section label="Plataforma">
                {row.platform} · {row.device_model} · v{row.app_version}
              </Section>
              {row.error ? (
                <Section label="Error">
                  <pre className="whitespace-pre-wrap rounded bg-muted p-2 text-xs">
                    {row.error}
                  </pre>
                </Section>
              ) : null}
              {row.stack_trace ? (
                <Section label="Stack trace">
                  <pre className="max-h-80 overflow-auto whitespace-pre rounded bg-muted p-2 font-mono text-xs leading-relaxed">
                    {row.stack_trace}
                  </pre>
                </Section>
              ) : null}
              {row.context != null ? (
                <Section label="Contexto">
                  <pre className="max-h-80 overflow-auto whitespace-pre-wrap rounded bg-muted p-2 font-mono text-xs">
                    {JSON.stringify(row.context, null, 2)}
                  </pre>
                </Section>
              ) : null}
            </div>
          </>
        ) : null}
      </SheetContent>
    </Sheet>
  );
}

function Section({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <div className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        {label}
      </div>
      <div>{children}</div>
    </div>
  );
}
