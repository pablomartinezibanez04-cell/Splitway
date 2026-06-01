// admin/app/(dashboard)/sessions/runs/[id]/sector-summaries.tsx
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type SectorSummary = {
  sectorId?: string;
  label?: string;
  index?: number;
  timeMs?: number;
  avgSpeedMps?: number;
};

function parseSectors(json: unknown): SectorSummary[] {
  if (!Array.isArray(json)) return [];
  return json.filter((x): x is SectorSummary => typeof x === "object" && x !== null);
}

export function SectorSummaries({ json }: { json: unknown }) {
  const sectors = parseSectors(json);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Sectores</CardTitle>
      </CardHeader>
      <CardContent>
        {sectors.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            Sin información de sectores.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="w-12">#</TableHead>
                <TableHead>Etiqueta</TableHead>
                <TableHead className="text-right">Tiempo</TableHead>
                <TableHead className="text-right">Vel. media</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sectors.map((s, i) => (
                <TableRow key={s.sectorId ?? i}>
                  <TableCell className="text-muted-foreground">
                    {(s.index ?? i) + 1}
                  </TableCell>
                  <TableCell>{s.label ?? "—"}</TableCell>
                  <TableCell className="text-right">
                    {s.timeMs != null
                      ? `${(s.timeMs / 1000).toFixed(2)} s`
                      : "—"}
                  </TableCell>
                  <TableCell className="text-right">
                    {s.avgSpeedMps != null
                      ? `${(s.avgSpeedMps * 3.6).toFixed(1)} km/h`
                      : "—"}
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
