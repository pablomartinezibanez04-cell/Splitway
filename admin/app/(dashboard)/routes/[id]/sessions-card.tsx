// admin/app/(dashboard)/routes/[id]/sessions-card.tsx
import { format } from "date-fns";
import { adminClient } from "@/lib/supabase/admin";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export async function SessionsCard({ routeId }: { routeId: string }) {
  const supabase = adminClient();
  const { data: sessions } = await supabase
    .from("session_runs")
    .select("id, owner_id, started_at, status, total_distance_m, avg_speed_mps")
    .eq("route_id", routeId)
    .order("started_at", { ascending: false })
    .limit(100);

  const ownerIds = Array.from(
    new Set((sessions ?? []).map((s) => s.owner_id)),
  );
  const { data: owners } =
    ownerIds.length > 0
      ? await supabase
          .from("profiles")
          .select("id, nickname")
          .in("id", ownerIds)
      : { data: [] as { id: string; nickname: string }[] };
  const nicknameById = new Map(
    (owners ?? []).map((o) => [o.id, o.nickname] as const),
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sesiones recientes</CardTitle>
      </CardHeader>
      <CardContent>
        {!sessions || sessions.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Sin sesiones en esta ruta.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Usuario</TableHead>
                <TableHead className="w-32">Cuando</TableHead>
                <TableHead className="w-24">Estado</TableHead>
                <TableHead className="w-24 text-right">Dist. (m)</TableHead>
                <TableHead className="w-28 text-right">Vel. media</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sessions.map((s) => (
                <TableRow key={s.id}>
                  <TableCell>{nicknameById.get(s.owner_id) ?? "—"}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(s.started_at), "dd/MM/yyyy HH:mm")}
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline">{s.status}</Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    {Math.round(s.total_distance_m).toLocaleString("es-ES")}
                  </TableCell>
                  <TableCell className="text-right">
                    {(s.avg_speed_mps * 3.6).toFixed(1)} km/h
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
