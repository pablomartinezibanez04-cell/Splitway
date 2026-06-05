// admin/components/shared/telemetry-charts.tsx
"use client";

import dynamic from "next/dynamic";
import {
  cumulativeDistance,
  elapsedSeconds,
  type TelemetryRow,
} from "@/lib/sessions/telemetry";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

// recharts pulls in d3 helpers — load it only when this component
// actually renders (detail page only, not the list).
const LineChart = dynamic(
  () => import("recharts").then((m) => m.LineChart),
  { ssr: false },
);
const Line = dynamic(() => import("recharts").then((m) => m.Line), {
  ssr: false,
});
const XAxis = dynamic(() => import("recharts").then((m) => m.XAxis), {
  ssr: false,
});
const YAxis = dynamic(() => import("recharts").then((m) => m.YAxis), {
  ssr: false,
});
const Tooltip = dynamic(() => import("recharts").then((m) => m.Tooltip), {
  ssr: false,
});
const ResponsiveContainer = dynamic(
  () => import("recharts").then((m) => m.ResponsiveContainer),
  { ssr: false },
);
const CartesianGrid = dynamic(
  () => import("recharts").then((m) => m.CartesianGrid),
  { ssr: false },
);

export function TelemetryCharts({ rows }: { rows: TelemetryRow[] }) {
  if (rows.length < 2) {
    return (
      <p className="text-sm text-muted-foreground">
        Sin telemetría suficiente para dibujar gráficas.
      </p>
    );
  }

  const distances = cumulativeDistance(rows);
  const seconds = elapsedSeconds(rows);

  const speedData = rows.map((r, i) => ({
    t: Math.round(seconds[i]!),
    speed: r.speed_mps != null ? +(r.speed_mps * 3.6).toFixed(1) : null,
  }));

  const altitudeData = rows.map((r, i) => ({
    d: Math.round(distances[i]!),
    altitude: r.altitude_m,
  }));

  return (
    <div className="grid gap-4 md:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Velocidad (km/h)</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart
                data={speedData}
                margin={{ top: 8, right: 8, left: 0, bottom: 8 }}
              >
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis
                  dataKey="t"
                  tickFormatter={(s) => `${Math.round(s / 60)}m`}
                  label={{ value: "tiempo", position: "insideBottomRight", offset: -4 }}
                />
                <YAxis />
                <Tooltip
                  formatter={(v: unknown) => [`${v} km/h`, "Velocidad"]}
                  labelFormatter={(s: unknown) =>
                    `t = ${typeof s === "number" ? Math.round(s) : 0} s`
                  }
                />
                <Line
                  type="monotone"
                  dataKey="speed"
                  stroke="#2563eb"
                  dot={false}
                  isAnimationActive={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Altitud (m)</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-56">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart
                data={altitudeData}
                margin={{ top: 8, right: 8, left: 0, bottom: 8 }}
              >
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis
                  dataKey="d"
                  tickFormatter={(m) => `${(m / 1000).toFixed(1)}km`}
                  label={{ value: "distancia", position: "insideBottomRight", offset: -4 }}
                />
                <YAxis />
                <Tooltip
                  formatter={(v: unknown) => [`${v ?? "—"} m`, "Altitud"]}
                  labelFormatter={(d: unknown) =>
                    `dist = ${typeof d === "number" ? Math.round(d) : 0} m`
                  }
                />
                <Line
                  type="monotone"
                  dataKey="altitude"
                  stroke="#16a34a"
                  dot={false}
                  isAnimationActive={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
