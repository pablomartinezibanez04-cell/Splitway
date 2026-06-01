// admin/app/(dashboard)/users/[id]/routes-tab.tsx
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

export async function RoutesTab({ userId }: { userId: string }) {
  const supabase = adminClient();
  const { data: routes } = await supabase
    .from("route_templates")
    .select("id, name, difficulty, location_label, created_at")
    .eq("owner_id", userId)
    .order("created_at", { ascending: false });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Rutas creadas</CardTitle>
      </CardHeader>
      <CardContent>
        {!routes || routes.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Este usuario no ha creado rutas.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nombre</TableHead>
                <TableHead>Dificultad</TableHead>
                <TableHead>Ubicación</TableHead>
                <TableHead className="w-32">Creada</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {routes.map((r) => (
                <TableRow key={r.id}>
                  <TableCell className="font-medium">{r.name}</TableCell>
                  <TableCell>
                    <Badge variant="outline">{r.difficulty}</Badge>
                  </TableCell>
                  <TableCell>{r.location_label ?? "—"}</TableCell>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(r.created_at), "dd/MM/yyyy")}
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
