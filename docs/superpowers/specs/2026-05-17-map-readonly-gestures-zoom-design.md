# Design: Mapa de solo lectura — gestos deshabilitados y zoom más cercano

**Fecha:** 2026-05-17

## Contexto

`SplitwayMap` es el widget reutilizable que encapsula Mapbox en la app. Se usa tanto en el modo de dibujo de rutas (interactivo) como en vistas de solo lectura (editor de rutas, historial, sesión en vivo). Actualmente no hay diferencia de comportamiento entre ambos usos: el mapa siempre acepta gestos (pan, zoom, rotación) y encuadra la ruta con el mismo padding en todos los contextos.

## Objetivo

- Las vistas de previsualización de rutas no deben permitir mover ni hacer zoom manual al mapa.
- En esas mismas vistas, el encuadre automático de la ruta debe quedar más cercano (más zoom) para que la ruta sea más visible.

## Diseño

### Nuevo parámetro en `SplitwayMap`

```dart
const SplitwayMap({
  ...
  this.interactive = true,  // <-- nuevo
});

final bool interactive;
```

Por defecto `true` para no romper el comportamiento existente.

### Cuando `interactive = false`

**1. Deshabilitar gestos** (en `_onMapCreated`, tras crear los annotation managers):

```dart
if (!widget.interactive) {
  await map.gestures.updateSettings(mbx.GesturesSettings(
    scrollEnabled: false,
    rotateEnabled: false,
    pinchToZoomEnabled: false,
    doubleTapToZoomInEnabled: false,
    doubleTouchToZoomOutEnabled: false,
    quickZoomEnabled: false,
    pitchEnabled: false,
    pinchPanEnabled: false,
  ));
}
```

**2. Padding más ajustado en `_flyToFitRoute`**:

| Modo | top/bottom | left/right |
|---|---|---|
| `interactive = true` (actual) | 80 dp | 60 dp |
| `interactive = false` (nuevo) | 40 dp | 30 dp |

El padding más pequeño hace que la ruta ocupe más área del mapa → zoom efectivamente más cercano sin cambiar la lógica de `cameraForCoordinateBounds`.

### Call sites actualizados

Los tres usos en modo lectura pasan `interactive: false`:

| Archivo | Contexto |
|---|---|
| `lib/src/features/editor/route_editor_screen.dart` → `_RouteDetail` | Previsualización en el editor |
| `lib/src/features/session/live_session_screen.dart` | Vista previa antes de sesión |
| `lib/src/features/history/history_screen.dart` | Detalle de sesión grabada |

El modo dibujo (`_DrawingView`) no cambia — usa `interactive: true` (default).

## Ficheros afectados

- `movile_app/lib/src/shared/widgets/splitway_map.dart` — lógica principal
- `movile_app/lib/src/features/editor/route_editor_screen.dart`
- `movile_app/lib/src/features/session/live_session_screen.dart`
- `movile_app/lib/src/features/history/history_screen.dart`

## Sin cambios

- `RouteMapPainter` (fallback sin Mapbox): ya es estático por naturaleza, no necesita cambios.
- Lógica de dibujo, anotaciones, telemetría: sin tocar.
