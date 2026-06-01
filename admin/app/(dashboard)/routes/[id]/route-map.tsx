// admin/app/(dashboard)/routes/[id]/route-map.tsx
"use client";

import { useEffect, useRef } from "react";
import "mapbox-gl/dist/mapbox-gl.css";

type Coord = [number, number]; // [longitude, latitude]

export function RouteMap({
  coordinates,
  className,
}: {
  coordinates: Coord[];
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;
    if (coordinates.length < 2) return;
    const token = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
    if (!token) {
      // eslint-disable-next-line no-console
      console.warn(
        "[RouteMap] NEXT_PUBLIC_MAPBOX_TOKEN is not set; map will not render.",
      );
      return;
    }

    let map: import("mapbox-gl").Map | null = null;
    let cancelled = false;

    void (async () => {
      const mapboxgl = (await import("mapbox-gl")).default;
      if (cancelled) return;
      mapboxgl.accessToken = token;

      const lons = coordinates.map((c) => c[0]);
      const lats = coordinates.map((c) => c[1]);
      const minLon = Math.min(...lons);
      const maxLon = Math.max(...lons);
      const minLat = Math.min(...lats);
      const maxLat = Math.max(...lats);

      map = new mapboxgl.Map({
        container: containerRef.current!,
        style: "mapbox://styles/mapbox/outdoors-v12",
        bounds: [
          [minLon, minLat],
          [maxLon, maxLat],
        ],
        fitBoundsOptions: { padding: 32 },
        attributionControl: false,
      });

      map.on("load", () => {
        if (!map || cancelled) return;
        map.addSource("route", {
          type: "geojson",
          data: {
            type: "Feature",
            properties: {},
            geometry: { type: "LineString", coordinates },
          },
        });
        map.addLayer({
          id: "route-line",
          type: "line",
          source: "route",
          layout: { "line-join": "round", "line-cap": "round" },
          paint: {
            "line-color": "#2563eb",
            "line-width": 4,
          },
        });
      });
    })();

    return () => {
      cancelled = true;
      map?.remove();
    };
  }, [coordinates]);

  if (coordinates.length < 2) {
    return (
      <div
        className={
          "flex h-72 items-center justify-center rounded-md border bg-muted text-sm text-muted-foreground " +
          (className ?? "")
        }
      >
        Esta ruta no tiene suficientes puntos para dibujar.
      </div>
    );
  }

  if (!process.env.NEXT_PUBLIC_MAPBOX_TOKEN) {
    return (
      <div
        className={
          "flex h-72 items-center justify-center rounded-md border bg-muted text-sm text-muted-foreground " +
          (className ?? "")
        }
      >
        Configura <code className="mx-1">NEXT_PUBLIC_MAPBOX_TOKEN</code> en{" "}
        <code className="mx-1">.env.local</code> para ver el mapa.
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className={"h-72 w-full overflow-hidden rounded-md border " + (className ?? "")}
    />
  );
}
