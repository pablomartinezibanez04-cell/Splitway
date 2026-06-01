// admin/app/(dashboard)/sessions/free-rides/[id]/page.tsx
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
import { DeleteFreeRideDialog } from "./delete-dialog";

export const dynamic = "force-dynamic";

export default async function FreeRideDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("free_rides")
    .select(
      "id, owner_id, vehicle_id, name, description, location_label, started_at, ended_at, status",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();

  const [{ data: profile }, { data: vehicle }] = await Promise.all([
    supabase.from("profiles").select("nickname").eq("id", row.owner_id).maybeSingle(),
    row.vehicle_id
      ? supabase.from("vehicles").select("name").eq("id", row.vehicle_id).maybeSingle()
      : Promise.resolve({ data: null as { name: string } | null }),
  ]);

  const { data: telemetry } = await supabase
    .from("free_ride_telemetry")
    .select("ts, lat, lng, altitude_m, speed_mps")
    .eq("free_ride_id", id)
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
        <Link href="/sessions?tab=free-rides">← Volver a sesiones</Link>
      </Button>

      <div className="space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">
            {row.name || row.location_label || "Salida libre"}
          </h1>
          <Badge variant="outline">{row.status ?? "—"}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          Usuario: <span className="font-medium">{profile?.nickname ?? "—"}</span>
          {vehicle?.name ? ` · Vehículo: ${vehicle.name}` : ""}
        </p>
        {row.description ? (
          <p className="text-sm text-muted-foreground">{row.description}</p>
        ) : null}
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

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteFreeRideDialog freeRideId={id} />
      </div>
    </div>
  );
}
