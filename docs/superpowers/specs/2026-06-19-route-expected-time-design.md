# Tiempo normal de una ruta + comparación en el historial

**Fecha:** 2026-06-19
**Estado:** Diseño aprobado, pendiente de plan de implementación

## Objetivo

Cada ruta debe llevar un **"tiempo normal"** (cuánto se tarda en recorrerla a
velocidad de conducción normal). Ese dato:

1. Se calcula al **crear/guardar** una ruta.
2. Se muestra en los **datos de la ruta** (pantalla de detalle de ruta).
3. En el **historial**, al ver una sesión corrida sobre esa ruta, se muestra el
   tiempo real y el **% ganado/perdido** respecto al tiempo normal, con una
   flecha verde/roja al lado.

## Decisiones tomadas

| Tema | Decisión |
|------|----------|
| Origen del tiempo | Reutilizar el `duration` que **ya devuelve la Directions API** en el pegado a carretera (`snapToRoads`). Cero peticiones extra para rutas dibujadas a puntos. |
| Tramos freehand | Fallback: **una** llamada a Map Matching sobre el path final cuando la ruta contiene tramos a mano alzada (sin `duration` de Directions). |
| Sin red / fallo | Dejar el tiempo **vacío** (`null`). Recalcular de forma perezosa al abrir el detalle de la ruta cuando haya red. |
| Tiempo real comparado | Automático por tipo de ruta: circuito cerrado → **mejor vuelta**; ruta abierta → **duración total** de la sesión. |
| Semántica de flecha | Más rápido que el normal → **verde + flecha abajo**; más lento → **rojo + flecha arriba**. |
| Sync Supabase | **En alcance**: columna nueva + RPC actualizada + mapeo en cliente, para que el dato no se pierda al sincronizar. |

## Cómo se obtiene el tiempo de Mapbox

### Caso normal (rutas dibujadas a puntos) — sin peticiones extra

Al dibujar tocando puntos, la app ya llama a la **Directions API**
(`/directions/v5/mapbox/{profile}/...`) vía
`RoutingService.snapToRoads` para pegar el trazado a la carretera. Esa respuesta
**ya incluye `routes[0].duration`** (segundos), que hoy se descarta.

- Extender `snapToRoads` para devolver, además de la geometría, el `duration`.
- En `saveDraft()`, **sumar los `duration` de cada segmento** pegado. Esa suma es
  el tiempo normal, y corresponde **exactamente** a la geometría que se guarda
  (porque el path guardado *es* esa respuesta de Directions).

### Caso freehand — fallback con Map Matching (1 petición)

Los tramos `FreehandSegment` no se pegan a carretera, así que no tienen
`duration`. Si la ruta contiene **algún** tramo freehand:

- Hacer **una** llamada a Map Matching sobre el path final ensamblado:
  ```
  GET https://api.mapbox.com/matching/v5/mapbox/{profile}/{lon,lat;...}
        ?geometries=geojson&overview=full&access_token={TOKEN}
  ```
  - `{profile}` = perfil con el que se dibujó (`driving`/`walking`/`cycling`).
  - `{coordinates}` = path simplificado a **≤100 puntos** con `simplifyPath`
    (Douglas-Peucker, ya en el core), manteniendo inicio y fin.
- Respuesta:
  ```json
  { "code": "Ok", "matchings": [ { "confidence": 0.95, "duration": 73.6, ... } ] }
  ```
  - Si `code != "Ok"` o `matchings` vacío → `null`.
  - Si hay match → **sumar `duration` de todos los `matchings`** (normalmente 1;
    varios si el trazado se parte por huecos).

### Conversión y vacío

- Segundos → `Duration(milliseconds: (segundos * 1000).round())`.
- Cualquier fallo (sin red, token inválido, `NoMatch`, sin `routingService`) →
  `expectedDuration = null`. La ruta se guarda igualmente.

### Recalcular perezosamente

Cuando se abre `RouteDetailScreen` y `route.expectedDuration == null` y hay
`routingService` disponible, intentar calcular el tiempo (Map Matching sobre el
path guardado) y persistirlo. Así una ruta creada sin red obtiene su tiempo en
cuanto se vuelve a abrir con conexión, cumpliendo "vacío hasta tener red".

## Cambios por capa

### 1. Modelo (core) — `packages/splitway_core`

`RouteTemplate` ([route_template.dart](../../../packages/splitway_core/lib/src/models/route_template.dart)):

- Nuevo campo `final Duration? expectedDuration;`.
- Constructor opcional `this.expectedDuration`.
- `copyWith`: parámetro `Object? expectedDuration = _sentinel` (patrón nullable
  ya usado para `thumbnailUrl`/`updatedAt`).
- `toJson` / `fromJson`: clave `expectedDurationMs` (int, milisegundos).

### 2. Servicios de routing — `movile_app`

`RoutingService` ([routing_service.dart](../../../movile_app/lib/src/services/routing/routing_service.dart)):

- `snapToRoads` pasa a devolver geometría **y** duración. Propuesta: nuevo tipo
  de retorno ligero `SnapResult { List<GeoPoint> path; Duration? duration; }`,
  o un método paralelo. (El callsite live-snap solo usa `path`; el de `saveDraft`
  usa ambos.)
- Nuevo método `matchDuration(List<GeoPoint> path, {String profile})` que llama a
  Map Matching y devuelve `Duration?` (fallback freehand y recálculo perezoso).
  Reutiliza `_token`, `logHttp` y el manejo de errores existentes.

### 3. Editor — `route_editor_controller.dart`

`saveDraft()` ([route_editor_controller.dart:493](../../../movile_app/lib/src/features/editor/route_editor_controller.dart)):

- Acumular `Duration? expectedTotal` sumando la duración de cada `SnappedSegment`
  pegado (ya se llama a `snapToRoads` ahí).
- Si hay algún `FreehandSegment` (o algún segmento sin duración) → tras ensamblar
  `finalPath`, intentar `matchDuration(finalPath, profile: _routingProfile)`.
- Pasar `expectedDuration: expectedTotal` al construir el `RouteTemplate`.

### 4. Persistencia local (SQLite)

`SplitwayLocalDatabase` ([splitway_local_database.dart](../../../movile_app/lib/src/data/local/splitway_local_database.dart)):

- Subir `_schemaVersion` de **12 → 13**.
- Migración nueva en `_migrate`:
  ```dart
  if (from < 13 && to >= 13) {
    await db.execute(
      'ALTER TABLE route_templates ADD COLUMN expected_duration_ms INTEGER',
    );
  }
  ```

`LocalDraftRepository` ([local_draft_repository.dart](../../../movile_app/lib/src/data/repositories/local_draft_repository.dart)):

- `saveRouteTemplate`: añadir
  `'expected_duration_ms': route.expectedDuration?.inMilliseconds` al map de campos.
- Lectura de fila (`RouteTemplate(...)` ~línea 137): añadir
  `expectedDuration: (row['expected_duration_ms'] as int?) == null ? null : Duration(milliseconds: row['expected_duration_ms'] as int)`.
- Nuevo método `updateRouteExpectedDuration(String id, Duration? d)` para el
  recálculo perezoso (UPDATE de la columna **+ bump de `updated_at`**, para que
  el siguiente `sync()` lo suba vía last-write-wins en vez de quedarse en local).

### 5. Sync Supabase

**Migración SQL nueva** `supabase/migrations/2026XXXX_add_route_expected_duration.sql`:

1. Columna:
   ```sql
   ALTER TABLE public.route_templates
     ADD COLUMN IF NOT EXISTS expected_duration_ms bigint;
   ```
2. `DROP FUNCTION` de la firma antigua de `upsert_route_with_sectors` y
   `CREATE OR REPLACE` con el parámetro nuevo `p_expected_duration_ms bigint`
   añadido a la firma, al `INSERT (... expected_duration_ms)` y al
   `ON CONFLICT ... DO UPDATE SET expected_duration_ms = excluded.expected_duration_ms`.
   Rehacer `revoke`/`grant` con la nueva firma. (Patrón idéntico a
   [20260611000001](../../../supabase/migrations/20260611000001_upsert_route_with_sectors.sql).)

**Cliente** `SupabaseRepository` ([supabase_repository.dart](../../../movile_app/lib/src/data/repositories/supabase_repository.dart)):

- En el `rpc('upsert_route_with_sectors', ...)`: añadir
  `'p_expected_duration_ms': route.expectedDuration?.inMilliseconds`.
- En `_parseRoute`: leer `expected_duration_ms` y mapearlo a `expectedDuration`.

### 6. UI — detalle de ruta

`RouteDetailScreen` ([route_detail_screen.dart](../../../movile_app/lib/src/features/editor/route_detail_screen.dart)):

- Nuevo `BentoTile` **"Tiempo normal"** con `Formatters.duration(route.expectedDuration)`
  o `'—'` si es `null`. Icono `Icons.timer_outlined`.
- En `initState`/load: disparar el recálculo perezoso si procede (ver arriba).
- Strings i18n: `routeExpectedTimeLabel` (es/en).

### 7. UI — historial (% + flecha)

Widget reutilizable nuevo `TimeDeltaIndicator` (en `shared/widgets`):

- Entrada: `Duration expected`, `Duration actual`.
- `pct = (actual - expected) / expected * 100`.
- `actual < expected` (más rápido): verde, `Icons.arrow_downward`, `▼ N %`.
- `actual > expected` (más lento): rojo, `Icons.arrow_upward`, `▲ N %`.
- Texto y flecha comparten color (verde/rojo).

Selección del tiempo real (helper compartido):

```
actual = route.isClosed ? session.bestLap?.duration : session.totalDuration
```

- Si `expectedDuration == null` o `actual == null` → no se muestra el indicador.

Puntos de inserción:

- **Lista** — `_SessionTile` ([history_screen.dart](../../../movile_app/lib/src/features/history/history_screen.dart)):
  el `TimeDeltaIndicator` como chip (p. ej. en `trailing`, junto al chevron).
  Requiere que `_SessionTile` reciba la `route` (ya la recibe) para conocer
  `isClosed` y `expectedDuration`.
- **Detalle** — `SessionDetailScreen`: fila con "Tiempo normal: X", el tiempo
  real comparado y el `TimeDeltaIndicator`, cerca del bloque de tiempo total /
  selector de vuelta.

## Casos límite

- **Ruta sin `routingService`** (sin token Mapbox): nunca se calcula tiempo →
  `null`, no se muestra indicador. Sin crash.
- **Ruta abierta sin laps** y `totalDuration == null` (sesión sin fin): sin
  indicador.
- **Circuito cerrado sin vueltas completadas** (`bestLap == null`): sin indicador.
- **Rutas oficiales** descargadas: si el backend ya trae `expected_duration_ms`,
  se usa; si no, queda `null` (no se recalcula para rutas que no son del usuario).
- **`expected == 0`**: evitar división por cero → tratar como `null`.

## Pruebas

- **Core**: `RouteTemplate` round-trip JSON con y sin `expectedDuration`; `copyWith`
  respeta `null` explícito vs no-cambio.
- **RoutingService**: parseo de `duration` de Directions; parseo/suma de
  `matchings.duration` de Map Matching; `code != "Ok"` → `null`.
- **TimeDeltaIndicator**: signo, color y flecha para más rápido / más lento /
  igual; oculto si `expected` o `actual` nulos.
- **Selección de tiempo real**: closed → bestLap; open → totalDuration.
- **Migración SQLite**: abrir BD v12 y subir a v13 conserva rutas y añade la
  columna; rutas viejas leen `expectedDuration == null`.

## Fuera de alcance

- Tiempo "deportivo" / de piloto (Mapbox da tiempo de conducción normal, que es
  justo lo pedido: "tardar de normal").
- Edición manual del tiempo normal por el usuario.
- Recalcular en background masivo para todas las rutas existentes (solo perezoso
  al abrir el detalle).
