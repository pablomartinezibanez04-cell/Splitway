// admin/app/(dashboard)/sessions/speed-sessions/[id]/page.tsx
import Link from "next/link";
import { notFound } from "next/navigation";
import { adminClient } from "@/lib/supabase/admin";
import { requireAdmin } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { MetricsGrid } from "./metrics-grid";
import { DeleteSpeedSessionDialog } from "./delete-dialog";

export const dynamic = "force-dynamic";

export default async function SpeedSessionDetail({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  await requireAdmin();
  const { id } = await params;

  const supabase = adminClient();
  const { data: row } = await supabase
    .from("speed_sessions")
    .select(
      "id, user_id, vehicle_id, name, selected_metrics, results, countdown_seconds, is_partial, started_at, finished_at, created_at, deleted_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (!row || row.deleted_at != null) notFound();

  const [{ data: profile }, { data: vehicle }] = await Promise.all([
    supabase.from("profiles").select("nickname").eq("id", row.user_id).maybeSingle(),
    row.vehicle_id
      ? supabase.from("vehicles").select("name").eq("id", row.vehicle_id).maybeSingle()
      : Promise.resolve({ data: null as { name: string } | null }),
  ]);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <Button asChild variant="ghost" size="sm">
        <Link href="/sessions?tab=speed-sessions">← Volver a sesiones</Link>
      </Button>

      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-2xl font-semibold">{row.name}</h1>
          {row.is_partial ? (
            <Badge variant="secondary">Parcial</Badge>
          ) : (
            <Badge variant="outline">Completa</Badge>
          )}
        </div>
        <p className="text-sm text-muted-foreground">
          Usuario: <span className="font-medium">{profile?.nickname ?? "—"}</span>
          {vehicle?.name ? ` · Vehículo: ${vehicle.name}` : ""}
        </p>
        <p className="text-xs text-muted-foreground">
          Métricas seleccionadas:{" "}
          {(row.selected_metrics ?? []).join(", ") || "—"}
        </p>
      </div>

      <MetricsGrid json={row.results} />

      <div className="space-y-3">
        <h2 className="text-lg font-semibold text-destructive">
          Zona peligrosa
        </h2>
        <DeleteSpeedSessionDialog speedSessionId={id} />
      </div>
    </div>
  );
}
