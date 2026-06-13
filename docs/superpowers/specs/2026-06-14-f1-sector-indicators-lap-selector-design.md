# Indicadores F1 de sector en sesión + selector de vueltas en historial

Fecha: 2026-06-14
Estado: Aprobado

## Objetivo

Rediseñar el panel inferior de la pantalla de sesión en vivo para mostrar indicadores
tipo F1 (vuelta actual, mejor vuelta y chips de sector coloreados), y reestructurar el
detalle de sesión en el historial para mostrar los datos por vuelta con un selector de
vueltas y chips de sector coloreados.

La app es mono-usuario por dispositivo (datos owner-scoped), por lo que:
- "marca personal" / "mejor de la sesión" = mejor tiempo de ese sector en la sesión actual.
- "récord del circuito de todas las sesiones" = mejor tiempo de ese sector en todas las
  sesiones del usuario en esa ruta.

## Lógica de colores (núcleo de la feature)

Función pura y testeable `sectorChipColor`:

Entradas:
- `lapTime`: tiempo del sector en la vuelta que se evalúa.
- `sessionCrossings`: lista de duraciones de ese sector en la sesión actual (incluye `lapTime`).
- `historicalRecord`: mejor tiempo histórico de ese sector en la ruta (puede ser `null`).

Cálculo:
- `sessionBest = min(sessionCrossings)`
- `overallBest = historicalRecord == null ? sessionBest : min(historicalRecord, sessionBest)`

Resultado:
- **Morado** (`#7B1FA2`) si `lapTime <= overallBest` → récord absoluto del circuito.
- **Verde** (`#43A047`) si no, pero `lapTime <= sessionBest` → mejor de la sesión.
- **Naranja** (`#FB8C00`) en el resto → por debajo de la mejor marca de la sesión.

Estado adicional para el directo:
- **Gris** cuando el sector aún no se ha cruzado en la vuelta actual (sin tiempo).

Notas:
- Cuando `historicalRecord` ya incluye la sesión actual (caso historial, que carga todas
  las sesiones de la ruta), `overallBest == historicalRecord`; la función sigue siendo
  correcta porque `sessionBest` es un subconjunto.
- Empates (`<=`) cuentan a favor del color mejor (morado/verde).

La función vive en un archivo nuevo y compartido, sin dependencias de UI salvo `Color`
(p. ej. `movile_app/lib/src/shared/widgets/sector_chip.dart` o un helper aparte), para
poder testearla de forma aislada.

## Datos disponibles

### Core (`packages/splitway_core`)
- `TrackingEngine`: añadir getter `List<SectorSummary> get sectorSummaries` que expone
  `_sectorSummaries` (sin copiar la lógica; solo lectura inmutable).
- `LiveTrackingController`: exponer `List<SectorSummary> get sectorSummaries =>
  _engine.sectorSummaries`.

### Controlador de sesión (`live_session_controller.dart`)
- En `startSession()`, antes/al iniciar, cargar `getSessionsByRoute(route.id)` y calcular
  `Map<String, Duration> historicalSectorRecords` = mínimo por `sectorId` de los
  `sectorSummaries` de esas sesiones.
- Exponer getter público `Map<String, Duration> get historicalSectorRecords`.
- Si la carga falla, usar un mapa vacío (degradación: no habrá morado por historial).

## Panel en vivo (`live_session_screen.dart` → `_buildRunning`)

Cambios dentro del contenedor negro inferior:
- **Eliminar** `_MetricsRow` (nº de vuelta, tiempo de vuelta, mejor vuelta combinados) y
  `_LastEventTile` (último sector + tiempo).
- **Añadir** una fila de dos indicadores grandes:
  - Izquierda: **VUELTA ACTUAL** — cronómetro de la vuelta en curso
    (`snapshot.currentLapElapsed`).
  - Derecha: **MEJOR VUELTA** — `snapshot.bestLap` de la sesión (placeholder "—" si `null`).
- **Chips de sector** (solo si la ruta tiene sectores): fila con tantos chips como sectores
  (`route.sectors` ordenados por `order`), numerados S1…Sn. Cada chip:
  - Gris hasta que el sector se cruza en la **vuelta actual** (`snapshot.currentLap`).
  - Al cruzarse, se colorea con `sectorChipColor` usando:
    - `lapTime` = duración del cruce de ese sector en la vuelta actual.
    - `sessionCrossings` = duraciones de todos los cruces de ese sector en
      `tracker.sectorSummaries`.
    - `historicalRecord` = `historicalSectorRecords[sectorId]`.
  - En vivo el chip **no** muestra el tiempo (solo número + color).
  - Se reinician a gris al empezar cada vuelta (al cambiar `snapshot.currentLap` ya no hay
    cruces de esa vuelta para los sectores aún no pasados).
- **Rutas abiertas** (`!route.isClosed`): ocultar VUELTA ACTUAL / MEJOR VUELTA (no hay
  vueltas); mostrar solo el cronómetro de pasada + los chips de sector si los hay.
- **Conservar** los botones de grabación (`_SessionRecordingActions`: Pausar → Reanudar +
  Finalizar).
- **Conservar** el toggle de simulación `_SimulationToggle` (solo admin + fuente simulada;
  es control de desarrollo, no indicador de sesión).
- El badge de GPS y el aviso de permiso de fondo no cambian (están fuera del contenedor).

## Detalle en Historial (`SessionDetailScreen` en `history_screen.dart`)

Para sesiones **con vueltas**:
- Mantener mapa + fecha.
- Cargar `getSessionsByRoute(route.id)` para calcular `historicalSectorRecords` y colorear
  los chips igual que en vivo.
- **Desplegable de vueltas**: por defecto seleccionada la **mejor vuelta**
  (`session.bestLap`). Cada ítem muestra "Vuelta N" y de subtítulo su tiempo. Al cambiar la
  selección se actualiza todo lo de abajo.
- Para la vuelta seleccionada:
  - **Fila resumen por vuelta** (sustituye a la de sesión):
    - Distancia: `lap.distanceMeters`.
    - Velocidad media: `lap.avgSpeedMps`.
    - Velocidad máxima: máximo de `speedMps` sobre los puntos de telemetría dentro de
      `[lap.startedAt, lap.endedAt]` (los puntos se cargan con
      `getSessionRun(includePoints: true)`).
  - **Tiempo** de la vuelta (destacado).
  - **Chips de sector coloreados** para esa vuelta (mismo widget compartido y misma lógica
    `sectorChipColor`), y en historial **sí muestran el tiempo** de cada sector debajo del
    número. `sessionCrossings` = cruces de ese sector en `session.sectorSummaries` de toda
    la sesión; `historicalRecord` = `historicalSectorRecords[sectorId]`.

Para sesiones **sin vueltas** (rutas abiertas):
- Mantener el comportamiento actual: fila resumen de la sesión + lista de sectores, sin
  desplegable.

## Widget de chip de sector

Widget compartido entre vivo e historial:
- Entradas: número de sector, color (o nulo/gris), y `time` opcional (`Duration?`).
- En vivo: `time` nulo → solo número + color.
- En historial: `time` no nulo → número + color + tiempo formateado debajo.
- Formato de tiempo con `Formatters.duration(..., dotSeparator: settings.timeFormatDot)`.

## Localización

- Añadir cadenas es/en necesarias para:
  - Etiqueta de ítem del desplegable "Vuelta N" (si no existe ya una reutilizable).
  - Cualquier etiqueta nueva del resumen por vuelta.
- Reutilizar las existentes cuando sea posible: `sessionCurrentLapLabel`,
  `sessionBestLapLabel`, `historyLapsLabel`, `sessionLapNumber`, `historyDistanceLabel`,
  `historyMaxSpeedLabel`, `historyAvgSpeedLabel`, `historySectorsLabel`.

## Tests

- Unitario de `sectorChipColor`: morado (récord absoluto), verde (mejor de sesión, no
  récord histórico), naranja (por debajo de la mejor de sesión), gris/sin tiempo, y casos
  con `historicalRecord == null` (primera sesión: la mejor marca es morada).
- Core: test del getter `sectorSummaries` en `TrackingEngine` / `LiveTrackingController`.
- Helper de velocidad máxima por vuelta (filtrado de puntos por ventana temporal): test
  unitario si se extrae como función pura.
- Widget tests: extender `live_session_screen_l10n_test.dart` (indicadores y chips
  presentes; ausencia de los antiguos) e `history_screen_l10n_test.dart` (desplegable de
  vueltas, resumen por vuelta, chips coloreados con tiempo).

## Archivos a tocar

- `packages/splitway_core/lib/src/tracking/tracking_engine.dart` — getter `sectorSummaries`.
- `movile_app/lib/src/services/tracking/live_tracking_controller.dart` — getter
  `sectorSummaries`.
- `movile_app/lib/src/features/session/live_session_controller.dart` — carga de récords
  históricos + getter.
- `movile_app/lib/src/features/session/live_session_screen.dart` — nuevo panel inferior.
- `movile_app/lib/src/features/history/history_screen.dart` — `SessionDetailScreen` con
  selector de vueltas, resumen por vuelta y chips coloreados.
- `movile_app/lib/src/shared/widgets/sector_chip.dart` (nuevo) — widget de chip + función
  `sectorChipColor` (o función en archivo aparte si se prefiere separar UI de lógica).
- `movile_app/lib/l10n/app_es.arb` y `app_en.arb` — cadenas nuevas.
- Tests correspondientes.

## Fuera de alcance (YAGNI)

- Sincronización/persistencia de récords entre dispositivos o usuarios.
- Colores configurables o leyenda explicativa de la paleta.
- Cambios en el panel de administración web.
