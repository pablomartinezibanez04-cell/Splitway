// admin/app/(dashboard)/users/[id]/activity-tab.tsx
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

type Activity = {
  kind: "session_run" | "free_ride" | "speed_session";
  id: string;
  created_at: string;
  label: string;
};

export async function ActivityTab({ userId }: { userId: string }) {
  const supabase = adminClient();

  const [runs, rides, speeds] = await Promise.all([
    supabase
      .from("session_runs")
      .select("id, started_at, status")
      .eq("owner_id", userId)
      .order("started_at", { ascending: false })
      .limit(50),
    supabase
      .from("free_rides")
      .select("id, started_at, name, location_label")
      .eq("owner_id", userId)
      .order("started_at", { ascending: false })
      .limit(50),
    supabase
      .from("speed_sessions")
      .select("id, started_at, name")
      .eq("user_id", userId)
      .order("started_at", { ascending: false })
      .limit(50),
  ]);

  const all: Activity[] = [
    ...(runs.data ?? []).map((r) => ({
      kind: "session_run" as const,
      id: r.id,
      created_at: r.started_at,
      label: `Sesión cronometrada (${r.status})`,
    })),
    ...(rides.data ?? []).map((r) => ({
      kind: "free_ride" as const,
      id: r.id,
      created_at: r.started_at,
      label: r.name || r.location_label || "Salida libre",
    })),
    ...(speeds.data ?? []).map((s) => ({
      kind: "speed_session" as const,
      id: s.id,
      created_at: s.started_at,
      label: s.name || "Drag strip",
    })),
  ]
    .sort((a, b) => b.created_at.localeCompare(a.created_at))
    .slice(0, 100);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Actividad reciente</CardTitle>
      </CardHeader>
      <CardContent>
        {all.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sin actividad.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Tipo</TableHead>
                <TableHead>Descripción</TableHead>
                <TableHead className="w-32">Cuando</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {all.map((a) => (
                <TableRow key={`${a.kind}:${a.id}`}>
                  <TableCell>
                    <Badge variant="outline">{a.kind}</Badge>
                  </TableCell>
                  <TableCell>{a.label}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(a.created_at), "dd/MM/yyyy HH:mm")}
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
