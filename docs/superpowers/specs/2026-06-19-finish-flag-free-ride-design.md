# Bandera de meta en free rides — diseño

Fecha: 2026-06-19

## Problema

La bandera de cuadros (marcador de meta) que aparece al correr una sesión solo
se pinta para rutas basadas en `RouteTemplate`, en su `startFinishGate`. Las
free ride se renderizan únicamente como traza de telemetría (punto a punto, sin
`startFinishGate`), así que no muestran ningún marcador de meta ni en vivo ni en
el historial.

Queremos que la bandera aparezca de forma consistente allí donde se pinta una
free ride terminada, dando una pista de dónde acaba el recorrido.

## Alcance

- **Free ride**: bandera de cuadros en el último punto de la traza, solo en
  vistas de recorrido terminado (resultado e historial). Nunca durante la
  grabación, porque el final aún no se conoce.
- **Rutas a mano**: sin cambios funcionales; ya pintan la bandera vía `route`.
- Una sola bandera de meta por mapa. No se añade marcador de inicio
  (decisión del usuario).

## Mecanismo: parámetro `finishMarker`

### `SplitwayMap` (`splitway_map.dart`)

- Nuevo parámetro `GeoPoint? finishMarker`.
- Se extrae el dibujo de la bandera a un helper `_createFinishFlag(GeoPoint)`
  que reutiliza `_finishMarkerManager` y `_finishFlagImageBytes`.
- Dentro de la guarda `!useHeatmap` se calcula el punto de meta:
  `route != null ? route.startFinishGate.center : finishMarker`. Si no es nulo,
  se pinta la bandera ahí.
- Igual que hoy, la bandera queda **oculta cuando el heatmap está activo**
  (mismo comportamiento para rutas y free rides).

### `RouteMapPainter` (`route_map_painter.dart`)

- Nuevo parámetro `GeoPoint? finishMarker`.
- La bandera se pinta en `finishMarker ?? route?.startFinishGate.center`.
- Mantiene el fallback sin Mapbox y los tests de widget.

### `SpeedHeatmapMapCard` (`speed_heatmap_map_card.dart`)

- Nuevo parámetro `GeoPoint? finishMarker`, propagado a `SplitwayMap`.

## Puntos de uso

- Free ride resultado (`free_ride_screen.dart`): `finishMarker` = último punto
  de `result.points` (si no está vacío).
- Free ride en historial (`history_screen.dart`): `finishMarker` = último punto
  de `_ride!.points` (si no está vacío).
- Rutas (detalle, sesión en vivo, sesión terminada): sin cambios.

## Casos borde

- Traza vacía → `finishMarker` nulo → no se pinta nada.
- Heatmap activo → bandera oculta.
- Free ride en vivo/grabando → sin bandera.

## Tests

- Widget test que verifique que `SplitwayMap` y `RouteMapPainter` aceptan
  `finishMarker` sin romper el render (fallback painter), siguiendo el patrón de
  los tests existentes.
