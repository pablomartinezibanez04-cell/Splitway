// admin/app/(dashboard)/sessions/runs/[id]/page.tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { RouteMap } from "@/app/(dashboard)/routes/[id]/route-map";
import { TelemetryCharts } from "@/components/shared/telemetry-charts";
import { toCoords, type TelemetryRow } from "@/lib/sessions/telemetry";
import { SectorSummaries } from "./sector-summaries";
import { DeleteSessionRunDialog } from "./delete-dialog";

export const dynamic = "force-dynamic";

export default async function SessionRunDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  // Fetch from session_runs directly because the view doesn't expose
  // sector_summaries_json. Joins are done as separate one-shot lookups
  // — cheap for a detail page.
  const { data: row } = await supabase
    .from("session_runs")
    .select(
      "id, owner_id, route_id, vehicle_id, started_at, ended_at, status, sector_summaries_json",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();

  const [{ data: profile }, { data: routeRow }, { data: vehicle }] =
    await Promise.all([
      supabase
        .from("profiles")
        .select("nickname")
        .eq("id", row.owner_id)
        .maybeSingle(),
      row.route_id
        ? supabase
            .from("route_templates")
            .select("name")
            .eq("id", row.route_id)
            .maybeSingle()
        : Promise.resolve({ data: null as { name: string } | null }),
      row.vehicle_id
        ? supabase
            .from("vehicles")
            .select("name")
            .eq("id", row.vehicle_id)
            .maybeSingle()
        : Promise.resolve({ data: null as { name: string } | null }),
    ]);

  const { data: telemetry } = await supabase
    .from("telemetry_points")
    .select("ts, lat, lng, altitude_m, speed_mps")
    .eq("session_id", id)
    .order("ts", { ascending: true });

  const rows: TelemetryRow[] = (telemetry ?? []).map((r) => ({
    ts: r.ts,
    lat: r.lat,
    lng: r.lng,
    altitude_m: r.altitude_m,
    speed_mps: r.speed_mps,
  }));

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/sessions?tab=runs">← Volver a sesiones</Link>
      </Button>

      <div className="space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">
            Sesión de {profile?.nickname ?? "—"}
          </h1>
          <Badge variant="outline">{row.status ?? "—"}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          Ruta: <span className="font-medium">{routeRow?.name ?? "—"}</span>
          {vehicle?.name ? ` · Vehículo: ${vehicle.name}` : ""}
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recorrido</CardTitle>
        </CardHeader>
        <CardContent>
          <RouteMap coordinates={toCoords(rows)} />
        </CardContent>
      </Card>

      <TelemetryCharts rows={rows} />

      <SectorSummaries json={row.sector_summaries_json ?? null} />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteSessionRunDialog sessionId={id} />
      </div>
    </div>
  );
}
