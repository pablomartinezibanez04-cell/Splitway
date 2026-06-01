// admin/app/(dashboard)/users/[id]/logs-tab.tsx
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

const LEVEL_COLOR: Record<string, "default" | "secondary" | "destructive" | "outline"> = {
  debug: "outline",
  info: "secondary",
  warning: "default",
  error: "destructive",
};

export async function LogsTab({ userId }: { userId: string }) {
  const supabase = adminClient();
  const { data: logs } = await supabase
    .from("app_logs")
    .select("id, timestamp, level, tag, message, app_version, platform")
    .eq("user_id", userId)
    .order("timestamp", { ascending: false })
    .limit(100);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Logs recientes</CardTitle>
      </CardHeader>
      <CardContent>
        {!logs || logs.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Este usuario no tiene logs (el viewer completo llega en F6).
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-32">Cuando</TableHead>
                <TableHead className="w-20">Nivel</TableHead>
                <TableHead className="w-28">Tag</TableHead>
                <TableHead>Mensaje</TableHead>
                <TableHead className="w-24">Versión</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {logs.map((l) => (
                <TableRow key={l.id}>
                  <TableCell className="text-muted-foreground">
                    {format(new Date(l.timestamp), "dd/MM HH:mm:ss")}
                  </TableCell>
                  <TableCell>
                    <Badge variant={LEVEL_COLOR[l.level] ?? "outline"}>
                      {l.level}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {l.tag}
                  </TableCell>
                  <TableCell className="text-sm">{l.message}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {l.app_version} ({l.platform})
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
