// admin/app/(dashboard)/users/[id]/garage-tab.tsx
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

export async function GarageTab({ userId }: { userId: string }) {
  const supabase = adminClient();
  const { data: vehicles } = await supabase
    .from("vehicles")
    .select("id, name, type, model, year, horsepower")
    .eq("user_id", userId)
    .order("created_at", { ascending: false });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Garaje</CardTitle>
      </CardHeader>
      <CardContent>
        {!vehicles || vehicles.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Este usuario no tiene vehículos.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Nombre</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Modelo</TableHead>
                <TableHead>Año</TableHead>
                <TableHead>CV</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {vehicles.map((v) => (
                <TableRow key={v.id}>
                  <TableCell className="font-medium">{v.name}</TableCell>
                  <TableCell>
                    <Badge variant="outline">{v.type}</Badge>
                  </TableCell>
                  <TableCell>{v.model ?? "—"}</TableCell>
                  <TableCell>{v.year ?? "—"}</TableCell>
                  <TableCell>{v.horsepower ?? "—"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
