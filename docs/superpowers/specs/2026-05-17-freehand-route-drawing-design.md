# Dibujo de rutas a mano alzada — Documento de diseño

**Fecha:** 2026-05-17
**Estado:** Aprobado (diseño)

## Problema

El editor de rutas actual construye el trazado por toques: cada toque añade un
waypoint y Mapbox Directions snapea los waypoints a carreteras reales. Esto falla
en dos casos:

1. **Rutas off-road**: Mapbox no genera camino donde no hay carretera reconocida.
2. **Calles no reconocidas / unión incorrecta**: Mapbox une dos puntos válidos
   por un sitio distinto al deseado.

Necesitamos una forma de dibujar a mano alzada con el dedo un tramo (o la ruta
entera) que **no** se snapee, generando los puntos necesarios para almacenarla.

## Decisiones de diseño (acordadas)

- El dibujo a mano es un **tercer modo** (`freehand`) junto a `appendPath` y
  `sectorPoint`. El trazo a mano se **añade al final** del path actual y **no se
  snapea**.
- Reducción de puntos: **muestreo por distancia + simplificación**
  (Douglas-Peucker).
- Gestos: en modo a mano se **desactiva el pan** del mapa pero se mantiene el
  **pinch-zoom**; el arrastre de un dedo dibuja.
- Modelo de guardado: **segmentos tipados, snap por tramos**.

## Arquitectura

El borrador deja de ser un modelo plano (`_rawWaypoints` + `_draftPath`) y pasa
a una **lista de segmentos tipados**:

- `DraftSegment` — tipo base sellado, con dos variantes:
  - `SnappedSegment`: `List<GeoPoint> waypoints` (toques del usuario) + caché
    `List<GeoPoint> snappedPath` (resultado de Mapbox, o waypoints en recto si
    no hay servicio / falla).
  - `FreehandSegment`: `List<GeoPoint> points` (ya simplificados tras soltar el
    dedo).
- El borrador es `List<DraftSegment> _segments`.
- `draftPath` pasa a ser un **getter calculado** que concatena, en orden, los
  puntos renderizados de cada segmento (snapped → `snappedPath`; freehand →
  `points`), evitando duplicar el punto de unión cuando coincide con el final
  del segmento anterior.
- `rawWaypoints` (círculos en el mapa) pasa a ser un getter que concatena los
  `waypoints` de los `SnappedSegment`.

### Helper puro en splitway_core

`simplifyPath(List<GeoPoint> points, double toleranceMeters) -> List<GeoPoint>`
implementando Douglas-Peucker con distancia perpendicular en metros. Vive en
`packages/splitway_core` para ser testeable sin Flutter. Casos:

- < 3 puntos → se devuelve la lista tal cual.
- Puntos colineales dentro de `tolerance` → se eliminan los intermedios.
- Siempre preserva el primer y último punto.

## Interacción y gestos

- Nuevo chip de modo **"A mano"** en la barra de modos del `_DrawingView`.
- `SplitwayMap` recibe una nueva propiedad `freehandMode: bool`. Cuando es
  `true`:
  - Desactiva el pan del mapa (`scrollEnabled: false`) pero mantiene
    `pinchToZoomEnabled: true` y `doubleTapToZoomInEnabled: true`.
  - Un overlay (`GestureDetector`) sobre el `MapWidget` captura el arrastre de
    un dedo:
    - `onPanStart(pos)` → inicia un `FreehandSegment` nuevo en el controller.
    - `onPanUpdate(pos)` → convierte la posición de pantalla a coordenada
      geográfica con `map.coordinateForPixel(...)`; si dista ≥ 5 m del último
      punto crudo capturado, se acumula.
    - `onPanEnd()` → el controller cierra el segmento: aplica
      `simplifyPath(crudo, 4.0)` y lo deja como `points` definitivos del
      `FreehandSegment`.
- El pinch de dos dedos lo sigue gestionando Mapbox (el `GestureDetector` solo
  reacciona a arrastre de un dedo).
- Con `scrollEnabled:false` el arrastre de un dedo no lo consume Mapbox, así que
  el overlay lo captura de forma fiable.
- `SplitwayMap` expone tres callbacks nuevos:
  `onFreehandStart()`, `onFreehandPoint(GeoPoint)` y `onFreehandEnd()`. La
  conversión pixel→geo ocurre dentro de `SplitwayMap` (es quien tiene el
  `MapboxMap`), de modo que el controller solo recibe `GeoPoint`.

## Generación de puntos y guardado

### Captura

- Durante el arrastre se descartan puntos a < 5 m del anterior.
- Al soltar, Douglas-Peucker (`toleranceMeters = 4.0`) reduce el trazo.

### `saveDraft` — snap por tramos

Para cada segmento, en orden:

- `SnappedSegment` → se snapea su lista de `waypoints` con
  `routingService.snapToRoads(...)`. Si falla o no hay servicio → se usan los
  waypoints crudos (líneas rectas), igual que el comportamiento actual.
- `FreehandSegment` → se usan sus `points` tal cual, **sin snap**.

Se concatenan los tramos resultantes en orden para formar el `path` final. Si el
primer punto de un tramo coincide (o está a < 1 m) con el último del tramo
anterior, se omite ese punto duplicado.

- **Circuito cerrado**: se calcula con el primer y último punto del path final
  (umbral 20 m, como hoy). Si es cerrado y los extremos no coinciden
  exactamente, se añade copia del primer punto al final.
- **Geocodificación inversa** y **`startFinishGate`** perpendicular: igual que
  hoy, sobre `path[0]` y `path[1]` del path final.
- `RouteTemplate` se construye igual que hoy (sectores a partir de
  `_draftSectorGates`).

## Undo, sectores, visual

### Undo

`undoLastPathPoint` se renombra a `undoLastAction`:

- Si el último segmento es `FreehandSegment` → se elimina el segmento completo.
- Si es `SnappedSegment` → se elimina su último waypoint; si queda con 0
  waypoints, se elimina el segmento. Tras quitar el waypoint, se reprograma el
  snap del segmento (o se limpia su caché si quedan < 2 waypoints).
- El botón "Deshacer" se habilita si existe algún segmento con contenido.

### Modo Sector

Sin cambios de lógica: `_nearestPathIndex` y `_gateAtPathIndex` siguen operando
sobre `draftPath` (ahora el getter concatenado). Requiere `draftPath.length ≥ 2`.

### Visual

- Tramos snapeados: morado `0xFF6A1B9A` (actual).
- Tramos a mano: naranja `0xFFEF6C00`, para distinguirlos en el mapa.
- `SplitwayMap._renderAnnotations` dibuja una polyline por segmento con su color
  según el tipo. Los círculos de waypoints solo para `SnappedSegment.waypoints`.

### Reglas de transición de modo

- En `appendPath`: un toque continúa el último `SnappedSegment` si el segmento
  activo es de ese tipo; si el último segmento es freehand (o no hay), se crea
  un `SnappedSegment` nuevo.
- En `freehand`: cada arrastre completo crea un `FreehandSegment` nuevo.
- `draftCanSave`: `draftPath.length ≥ 2` y nombre no vacío.

## Estrategia de tests

Unitarios en `splitway_core`:

- `simplifyPath`: recta colineal de N puntos → 2 puntos; ruido por debajo de
  tolerancia → se elimina; preserva extremos; < 3 puntos → identidad.

Tests de controller (`route_editor_controller_test.dart`):

- Añadir `SnappedSegment` + `FreehandSegment` + `SnappedSegment` → `saveDraft`
  produce un path concatenado donde los puntos freehand aparecen sin alterar y
  los snapped pasan por el `routingService` (fake).
- `undoLastAction` elimina el `FreehandSegment` completo.
- `undoLastAction` elimina el último waypoint de un `SnappedSegment`.
- Detección de circuito cerrado con path mixto (primer punto ≈ último).
- `draftCanSave` falso con < 2 puntos totales.

## Fuera de alcance (YAGNI)

- Insertar/reemplazar un trazo a mano entre dos puntos ya existentes del path
  (edición por índices). Sólo se añade al final.
- Snap parcial o suavizado del trazo a mano.
- Pantalla/lienzo de dibujo separado.
