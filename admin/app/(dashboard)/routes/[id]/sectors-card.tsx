// admin/app/(dashboard)/routes/[id]/sectors-card.tsx
import { adminClient } from "@/lib/supabase/admin";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export async function SectorsCard({ routeId }: { routeId: string }) {
  const supabase = adminClient();
  const { data: sectors } = await supabase
    .from("sectors")
    .select("id, label, order_index")
    .eq("route_id", routeId)
    .order("order_index", { ascending: true });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sectores</CardTitle>
      </CardHeader>
      <CardContent>
        {!sectors || sectors.length === 0 ? (
          <p className="text-sm text-muted-foreground">Sin sectores.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-16">#</TableHead>
                <TableHead>Etiqueta</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sectors.map((s) => (
                <TableRow key={s.id}>
                  <TableCell className="text-muted-foreground">
                    {s.order_index + 1}
                  </TableCell>
                  <TableCell>{s.label}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}
