// admin/app/(dashboard)/sessions/speed-sessions/[id]/metrics-grid.tsx
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

type Results = Record<string, { value: number | null; unit?: string }>;

function parseResults(json: unknown): Results {
  if (!json || typeof json !== "object" || Array.isArray(json)) return {};
  const out: Results = {};
  for (const [k, v] of Object.entries(json as Record<string, unknown>)) {
    if (v && typeof v === "object" && "value" in v) {
      const obj = v as { value?: unknown; unit?: unknown };
      out[k] = {
        value: typeof obj.value === "number" ? obj.value : null,
        unit: typeof obj.unit === "string" ? obj.unit : undefined,
      };
    } else if (typeof v === "number") {
      out[k] = { value: v };
    }
  }
  return out;
}

export function MetricsGrid({ json }: { json: unknown }) {
  const results = parseResults(json);
  const entries = Object.entries(results);
  if (entries.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        Esta sesión no registró ninguna métrica.
      </p>
    );
  }
  return (
    <div className="grid gap-3 sm:grid-cols-2 md:grid-cols-3">
      {entries.map(([key, m]) => (
        <Card key={key}>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground">
              {key}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-semibold">
              {m.value != null ? m.value.toFixed(2) : "—"}
              {m.unit ? (
                <span className="ml-1 text-sm text-muted-foreground">
                  {m.unit}
                </span>
              ) : null}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
