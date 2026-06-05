// admin/lib/sessions/telemetry.ts
// Pure helpers shared by the three detail pages. Both telemetry
// tables (telemetry_points and free_ride_telemetry) have the same
// row shape so a single set of helpers works.

export type TelemetryRow = {
  ts: string;
  lat: number;
  lng: number;
  altitude_m: number | null;
  speed_mps: number | null;
};

/** [lng, lat] pairs for Mapbox's LineString. */
export function toCoords(rows: TelemetryRow[]): [number, number][] {
  return rows.map((r) => [r.lng, r.lat]);
}

/** Haversine distance in meters between two lat/lng points. */
function haversineMeters(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** Cumulative distance (in meters) from row 0 to each subsequent row. */
export function cumulativeDistance(rows: TelemetryRow[]): number[] {
  const out: number[] = [];
  let total = 0;
  for (let i = 0; i < rows.length; i++) {
    if (i > 0) total += haversineMeters(rows[i - 1]!, rows[i]!);
    out.push(total);
  }
  return out;
}

/** Seconds elapsed from row 0 to each subsequent row. */
export function elapsedSeconds(rows: TelemetryRow[]): number[] {
  if (rows.length === 0) return [];
  const t0 = new Date(rows[0]!.ts).getTime();
  return rows.map((r) => (new Date(r.ts).getTime() - t0) / 1000);
}
