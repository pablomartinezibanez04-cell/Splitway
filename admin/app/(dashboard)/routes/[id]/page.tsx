// admin/app/(dashboard)/routes/[id]/page.tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { MetadataForm } from "./metadata-form";
import { OfficialControls } from "./official-toggle";
import { DeleteRouteDialog } from "./delete-dialog";
import { RouteMap } from "./route-map";
import { SectorsCard } from "./sectors-card";
import { SessionsCard } from "./sessions-card";

export const dynamic = "force-dynamic";

type Coord = [number, number];

function toCoords(pathJson: unknown): Coord[] {
  if (!Array.isArray(pathJson)) return [];
  const out: Coord[] = [];
  for (const p of pathJson) {
    if (
      p &&
      typeof p === "object" &&
      "longitude" in p &&
      "latitude" in p &&
      typeof (p as { longitude: unknown }).longitude === "number" &&
      typeof (p as { latitude: unknown }).latitude === "number"
    ) {
      out.push([
        (p as { longitude: number }).longitude,
        (p as { latitude: number }).latitude,
      ]);
    }
  }
  return out;
}

export default async function RouteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("route_templates")
    .select(
      "id, name, description, difficulty, location_label, is_official, owner_id, path_json, created_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row) notFound();

  const { data: owner } = await supabase
    .from("profiles")
    .select("nickname")
    .eq("id", row.owner_id)
    .maybeSingle();

  const coords = toCoords(row.path_json);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/routes">← Volver a rutas</Link>
      </Button>

      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">{row.name}</h1>
          {row.is_official ? <Badge variant="default">Oficial</Badge> : null}
          <Badge variant="outline">{row.difficulty}</Badge>
        </div>
        <p className="text-sm text-muted-foreground">
          {row.location_label ? row.location_label + " · " : ""}
          Propietario:{" "}
          <span className="font-medium">{owner?.nickname ?? "—"}</span>
        </p>
      </div>

      <RouteMap coordinates={coords} />

      <OfficialControls routeId={row.id} isOfficial={row.is_official} />

      <MetadataForm
        routeId={row.id}
        initialName={row.name}
        initialDescription={row.description ?? ""}
        initialDifficulty={row.difficulty}
        initialLocationLabel={row.location_label ?? ""}
      />

      <SectorsCard routeId={row.id} />
      <SessionsCard routeId={row.id} />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteRouteDialog routeId={row.id} routeName={row.name} />
      </div>
    </div>
  );
}
