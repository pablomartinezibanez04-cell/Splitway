# Diseño: contabilizar el sector final

Fecha: 2026-06-14

## Problema

Con N puertas de sector la ruta se divide en N+1 sectores, pero el motor solo
emite un `SectorSummary` al cruzar una puerta. Con 2 puertas (S1, S2) se
contabiliza inicio→S1 y S1→S2, pero el último tramo (S2→meta) nunca se mide ni
se muestra.

## Concepto

La última puerta "virtual" es la línea de salida/meta (rutas cerradas) o el
último punto del trazado (rutas abiertas). Se añade un sector final implícito
con un ID estable y constante, que se cuenta solo cuando la vuelta/ruta se
completa cruzando todas las puertas.

## Cambios

### 1. Núcleo (`packages/splitway_core`)

- Nueva constante exportada `kFinalSectorId = '__final__'`. No colisiona con los
  IDs reales de sector (`'<routeId>-sec-N'`).
- En `TrackingEngine`:
  - Al cerrar una vuelta (`_onStartFinishCrossed`, rama de cierre de ruta
    cerrada) y al terminar una ruta abierta (`_finishOpenRoute`): si hay
    sectores definidos y se cruzaron todas las puertas
    (`_orderedSectors.isNotEmpty && _nextSectorIndex >= _orderedSectors.length`),
    se emite un `SectorSummary` adicional con `sectorId = kFinalSectorId`, desde
    `_lastSectorAt` hasta el instante del cruce de meta, usando
    `_sectorDistanceAccumulator` para distancia y velocidad media (igual que
    `_onSectorCrossed`).
  - El evento `SectorCrossed(kFinalSectorId)` se emite antes de `LapClosed`.
  - Solo se registra si está completo: si el usuario para a mitad del último
    sector, no se registra (no se toca `finish()` para vueltas incompletas).

### 2. UI (movile_app)

Tres puntos, todos iteran `route.sectors`:

- `_LiveSectorChips` (panel en vivo) y chips de vuelta en historial
  (`_buildLapDetail`): renderizar un chip adicional `S${N+1}` cuyo tier y tiempo
  se buscan en los mapas con la clave `kFinalSectorId`. Solo se añade cuando
  `route.sectors` no está vacío (0 puertas sigue sin mostrar chips).
- Lista de sectores del historial (`orElse` de `firstWhere`): cuando
  `sec.sectorId == kFinalSectorId`, etiquetar como `Sector ${N+1}` en vez del ID
  crudo.

### 3. Comparación F1 / récords

Sin cambios: `_loadHistoricalSectorRecords` (history y live controller) y las
listas de tiempos ya se indexan por `sectorId`; el sector final comparte la
misma clave constante en todas las sesiones de la ruta.

### Sin cambios

Persistencia (`SectorSummary` ya serializa cualquier `sectorId`), modelo de
ruta y editor.

## Tests (TDD)

En `packages/splitway_core/test/tracking_engine_test.dart`:

- Ruta cerrada con 2 puertas: una vuelta completa produce 3 `SectorSummary`,
  el tercero con `kFinalSectorId` y duración = meta − S2.
- Ruta abierta con puertas: al terminar (proximidad al último punto) se registra
  el sector final.
- Vuelta que termina a mitad del último sector (no se cruzan todas las puertas):
  no se registra sector final.
