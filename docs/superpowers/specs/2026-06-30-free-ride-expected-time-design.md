# Tiempo normal (Mapbox) para free rides + comparación en el historial

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado, pendiente de plan de implementación

## Objetivo

Cada **free ride** debe llevar, igual que las rutas normales, un **"tiempo
normal"** (`expectedDuration`): cuánto se tarda en recorrer su trazado a
velocidad de conducción/marcha normal según Mapbox. Ese dato:

1. Se **calcula al acabar** el free ride, con **una** llamada a Mapbox (Map
   Matching) sobre el trazado GPS grabado.
2. Se **muestra en el historial** (lista y detalle del free ride) con el tiempo
   real total y el **% ganado/perdido**, con flecha verde/roja, exactamente como
   en las sesiones sobre rutas.
3. Si el free ride se **guarda como ruta** para otras sesiones, el tiempo se
   **hereda** (no se recalcula): se pasa el `expectedDuration` ya almacenado al
   `RouteTemplate` nuevo.

Reutiliza al máximo la infraestructura existente del "tiempo normal" de rutas
(ver [2026-06-19-route-expected-time-design.md](2026-06-19-route-expected-time-design.md)):
`RouteTemplate.expectedDuration`, `RoutingService.matchDuration`,
`TimeDeltaIndicator`, `Formatters.duration`, string `routeExpectedTimeLabel`.

## Decisiones tomadas

| Tema | Decisión |
|------|----------|
| Origen del tiempo | **Map Matching** (`RoutingService.matchDuration`) sobre el path GPS grabado. Un free ride no pega waypoints a carretera, así que no hay `duration` de Directions previa que reutilizar: siempre 1 petición al acabar. |
| Perfil Mapbox | **Según vehículo**: `bicycle → 'cycling'`; sin vehículo (a pie) → `'walking'`; resto (`car`/`motorcycle`/`goKart`/`other`) → `'driving'`. |
| Sin red / fallo | Dejar el tiempo **vacío** (`null`); el ride se guarda igual. Recalcular de forma **perezosa** al abrir el detalle del free ride cuando haya red. |
| Tiempo real comparado | Un free ride es siempre "ruta abierta" → **duración total** del ride (`FreeRideRun.totalDuration`). |
| Semántica de flecha | Reutiliza `TimeDeltaIndicator`: más rápido que el normal → verde + flecha abajo; más lento → rojo + flecha arriba. |
| Guardar como ruta | **Reutilizar** el `expectedDuration` del ride (no recalcular) al construir el `RouteTemplate`. |
| Sync Supabase | **En alcance**: columna nueva en `free_rides` + RPC `upsert_free_ride_with_telemetry` actualizada + mapeo en cliente, para que el dato no se pierda al sincronizar entre dispositivos. |

## Cómo se obtiene el tiempo de Mapbox

Al acabar la grabación (`FreeRideController.finishRecording`), tras construir el
`FreeRideRun`:

- Si hay `routingService` y `run.points.length >= 2`, llamar:
  ```
  routingService.matchDuration(run.path, profile: <perfil>)
  ```
  que llama a la Map Matching API
  (`/matching/v5/mapbox/{profile}/{lon,lat;...}`), capada a ≤100 puntos vía
  `simplifyPath`/`_sample` (ya existente). Devuelve `Duration?`.
- `<perfil>` se resuelve por el tipo del vehículo seleccionado (ver helper de
  perfil más abajo).
- Cualquier fallo (sin red, token inválido, `NoMatch`, sin `routingService`,
  <2 puntos) → `expectedDuration = null`. El ride se guarda igualmente.

### Recálculo perezoso

Al abrir `FreeRideDetailScreen`, si `ride.expectedDuration == null` y hay
`routingService` disponible, intentar `matchDuration` sobre el path guardado y
persistir el resultado vía `updateFreeRideExpectedDuration`. Así un ride acabado
sin cobertura obtiene su tiempo al reabrirlo con conexión. (Espejo del recálculo
perezoso de `RouteDetailScreen`.)

> **Nota DI:** `FreeRideDetailScreen` no recibe hoy `routingService`. El
> recálculo perezoso requiere inyectarlo (desde `_FreeRideTile` →
> `app_router`/`history_screen`). Si se prefiere acotar, el recálculo perezoso
> puede quedar **fuera de alcance** y dejar solo el cálculo en `finishRecording`;
> el diseño aprobado lo incluye.

## Mapeo de perfil por vehículo

Helper puro y testeable (p. ej. en `free_ride_screen.dart` o un util compartido):

```dart
String routingProfileForVehicle(VehicleType? type) => switch (type) {
      null => 'walking',                 // a pie
      VehicleType.bicycle => 'cycling',
      _ => 'driving',                    // car, motorcycle, goKart, other
    };
```

- `FreeRideController` solo guarda `selectedVehicleId` (String?), no el
  `Vehicle`. La **pantalla** (`free_ride_screen`, que ya tiene `garageService`)
  resuelve el `VehicleType` del vehículo seleccionado y pasa el perfil string a
  `finishRecording(routingProfile: ...)`. Así el controller no depende de
  `GarageService`.
- Por defecto, si no se pasa perfil → `'driving'`.

## Cambios por capa

### 1. Modelo (core) — `packages/splitway_core`

`FreeRideRun` ([free_ride_run.dart](../../../packages/splitway_core/lib/src/models/free_ride_run.dart)):

- Nuevo campo `final Duration? expectedDuration;`.
- Constructor opcional `this.expectedDuration`.
- `copyWith`: parámetro `Object? expectedDuration = _sentinel` (patrón nullable;
  añadir el `static const _sentinel = Object();` si no existe en este archivo).
- (No hay `toJson`/`fromJson` en `FreeRideRun`; el mapeo a fila lo hacen los
  repos, ver capas 3 y 4.)

### 2. Controller + servicios — `movile_app`

`FreeRideController`
([free_ride_controller.dart](../../../movile_app/lib/src/features/free_ride/free_ride_controller.dart)):

- Inyectar `RoutingService? routingService` en el constructor (junto a
  `geocodingService`).
- `finishRecording({String routingProfile = 'driving'})`: tras construir `run`,
  si `routingService != null` y `run.points.length >= 2`, intentar
  `matchDuration` y aplicar `run = run.copyWith(expectedDuration: ...)` **antes**
  de `_repo.saveFreeRideRun(run)`.

`AppRouter` ([app_router.dart:65](../../../movile_app/lib/src/routing/app_router.dart)):

- Pasar `routingService: config.hasMapbox ? RoutingService(mapboxToken: config.mapboxToken!) : null`
  al construir `_freeRideController`.

`FreeRideScreen` ([free_ride_screen.dart](../../../movile_app/lib/src/features/free_ride/free_ride_screen.dart)):

- Al llamar `ctrl.finishRecording(...)` (línea ~484), resolver el `VehicleType`
  del vehículo seleccionado (ya hay lógica similar en
  `_selectedVehicleIsMotorized`) y pasar
  `routingProfile: routingProfileForVehicle(type)`.

### 3. Persistencia local (SQLite)

`SplitwayLocalDatabase`
([splitway_local_database.dart](../../../movile_app/lib/src/data/local/splitway_local_database.dart)):

- Subir `_schemaVersion` **13 → 14**.
- Migración nueva en `_migrate`:
  ```dart
  if (from < 14 && to >= 14) {
    await db.execute(
      'ALTER TABLE free_rides ADD COLUMN expected_duration_ms INTEGER',
    );
  }
  ```
- Añadir la columna también a la creación de tabla `free_rides` (`_onCreate`),
  para BD nuevas.

`LocalDraftRepository`
([local_draft_repository.dart](../../../movile_app/lib/src/data/repositories/local_draft_repository.dart)):

- `saveFreeRideRun` (~:358): añadir
  `'expected_duration_ms': ride.expectedDuration?.inMilliseconds` al map.
- Lectura de fila (`FreeRideRun(...)` ~:481): añadir
  `expectedDuration: row['expected_duration_ms'] == null ? null : Duration(milliseconds: (row['expected_duration_ms'] as num).toInt())`.
- Nuevo método `updateFreeRideExpectedDuration(String id, Duration? d)` (UPDATE
  de la columna **+ bump de `updated_at`**, para que el siguiente `sync()` lo
  suba). Espejo de `updateRouteExpectedDuration`.

### 4. Sync Supabase

**Migración SQL nueva** `supabase/migrations/2026XXXX_add_free_ride_expected_duration.sql`:

1. Columna:
   ```sql
   ALTER TABLE public.free_rides
     ADD COLUMN IF NOT EXISTS expected_duration_ms bigint;
   ```
2. `DROP FUNCTION` de la firma **actual de 13 args** de
   `upsert_free_ride_with_telemetry` (la de
   [20260614000001](../../../supabase/migrations/20260614000001_free_ride_upsert_dedupe.sql),
   con `p_vehicle_id`) y `CREATE` con el parámetro nuevo
   `p_expected_duration_ms bigint default null` añadido a la firma, al
   `INSERT (... expected_duration_ms)`/`VALUES` y al
   `ON CONFLICT ... DO UPDATE SET expected_duration_ms = excluded.expected_duration_ms`.
   Mantener `set search_path = public` y el guard BUG-4. Rehacer `revoke`/`grant`
   con la nueva firma de 14 args.

**Cliente** `SupabaseRepository`
([supabase_repository.dart](../../../movile_app/lib/src/data/repositories/supabase_repository.dart)):

- En el `rpc('upsert_free_ride_with_telemetry', ...)` (~:256): añadir
  `'p_expected_duration_ms': ride.expectedDuration?.inMilliseconds`.
- En `_parseFreeRide` (~:450): leer `expected_duration_ms` y mapearlo a
  `expectedDuration` (`row['expected_duration_ms'] == null ? null : Duration(milliseconds: (row['expected_duration_ms'] as num).toInt())`).
- Asegurar que el `select` de free rides incluye la columna nueva (si usa `*`,
  nada que tocar; si lista columnas, añadir `expected_duration_ms`).

### 5. UI — historial

`history_screen.dart`
([history_screen.dart](../../../movile_app/lib/src/features/history/history_screen.dart)):

- **Lista** `_FreeRideTile` (~:1061): añadir, dentro del `subtitle` Column, un
  bloque `Builder` análogo al de `_SessionTile` (~:1019):
  ```dart
  final expected = ride.expectedDuration;
  final actual = ride.totalDuration;
  if (expected == null || actual == null) return const SizedBox.shrink();
  // Row: "Tiempo normal: <actual>" + TimeDeltaIndicator(expected, actual)
  ```
  Un free ride es siempre ruta abierta → `actual = totalDuration` directamente
  (no se usa `representativeRunTime`, que exige `RouteTemplate`).
- **Detalle** `_FreeRideSummaryRow` (~:1351): añadir una tarjeta "Tiempo normal"
  (`l.routeExpectedTimeLabel`, `Formatters.duration(...)` o `'—'`) y mostrar el
  `TimeDeltaIndicator` junto al tiempo total (`freeRideElapsedLabel`) cuando
  `expectedDuration` y `totalDuration` no sean nulos.
- `FreeRideDetailScreen`: disparar el recálculo perezoso en `_load`/`initState`
  si procede (ver "Recálculo perezoso"). Requiere `routingService` inyectado
  hasta esta pantalla.

### 6. Guardar como ruta

`FreeRideController.saveAsRoute`
([free_ride_controller.dart:298](../../../movile_app/lib/src/features/free_ride/free_ride_controller.dart)):

- Al construir el `RouteTemplate` (~:328), añadir
  `expectedDuration: run.expectedDuration`. Se **reutiliza** el valor ya
  calculado; el recálculo perezoso de `RouteDetailScreen` no se dispara porque
  ya viene poblado.

## Casos límite

- **Sin `routingService`** (sin token Mapbox): nunca se calcula → `null`, sin
  indicador, sin crash.
- **Free ride sin fin** (`totalDuration == null`): sin indicador.
- **`expected == 0` o no positivo**: `TimeDeltaIndicator`/`runDeltaPercent` ya lo
  tratan como sin indicador (división por cero evitada).
- **Free ride con <2 puntos**: no se llama a Map Matching → `null`.
- **Migración**: abrir BD v13 y subir a v14 conserva los free rides y añade la
  columna; rides viejos leen `expectedDuration == null` (y se recalculan
  perezosamente al abrir el detalle con red).
- **Guardar como ruta con `expectedDuration == null`** (ride acabado sin red y
  nunca reabierto): la ruta nace con `null` y la recalcula `RouteDetailScreen`
  perezosamente, como cualquier ruta. Sin regresión.

## Pruebas

- **Core**: `FreeRideRun.copyWith` respeta `null` explícito vs no-cambio para
  `expectedDuration`.
- **Mapeo de perfil**: `routingProfileForVehicle` para cada `VehicleType` y
  `null` (a pie → walking, bicycle → cycling, resto → driving).
- **RoutingService**: ya cubierto (parseo/suma de `matchings.duration`,
  `code != "Ok"` → `null`).
- **Repo local**: round-trip `saveFreeRideRun` → `getFreeRideRun` conserva
  `expectedDuration` (con valor y `null`); `updateFreeRideExpectedDuration`
  actualiza columna y `updated_at`.
- **Migración SQLite**: abrir BD v13, migrar a v14, columna presente y rides
  preservados con `expectedDuration == null`.
- **UI**: `_FreeRideTile` y detalle muestran/ocultan el `TimeDeltaIndicator`
  según haya o no `expectedDuration` + `totalDuration`.
- **saveAsRoute**: el `RouteTemplate` resultante hereda `run.expectedDuration`.

## Fuera de alcance

- Edición manual del tiempo normal por el usuario.
- Recálculo masivo en background de todos los free rides existentes (solo
  perezoso al abrir el detalle).
- Tiempo "deportivo" / de piloto (Mapbox da tiempo normal, que es lo pedido).
