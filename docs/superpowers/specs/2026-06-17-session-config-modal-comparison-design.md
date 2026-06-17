# Modal de configuración de sesión + elección de comparación

Fecha: 2026-06-17
Estado: aprobado (diseño)

## Resumen

Antes de empezar a grabar una sesión, el usuario configura la grabación en un
modal que aparece tras pulsar **"Comenzar grabación"**. El modal recopila el
vehículo, un nombre opcional, la fuente de telemetría (solo admin) y un checkbox
que decide si la sesión se compara contra el mejor tiempo histórico del usuario
en esa ruta.

Regla de comparación:

- **Rutas abiertas**: por defecto se compara contra el mejor histórico (el
  checkbox viene marcado, pero es editable).
- **Rutas cerradas (circuito)**: el usuario elige con el checkbox si compite
  contra su mejor histórico en la ruta, o solo contra su mejor vuelta de la
  sesión actual.

## Motivación

Hoy `_historicalSectorRecords` se carga **siempre** y pinta los chips de sector
"morados" (récord histórico). El usuario no tiene control sobre contra qué
compite. Además la configuración (vehículo, telemetría) está dispersa en la
pantalla previa. Este cambio centraliza la configuración en un único paso y da
al usuario control explícito sobre el rival de la sesión.

## Flujo

```
Pantalla "ready" (solo: selector de ruta + botón "Comenzar grabación")
   └─ pulsar "Comenzar grabación"
        └─ SessionConfigSheet (modal nuevo, casi pantalla completa)
             ├─ Vehículo (selector del garaje, reutiliza VehiclePickerTile)
             ├─ Nombre (opcional, TextField)
             ├─ Fuente de telemetría (SegmentedButton, solo si profile.isAdmin)
             ├─ Checkbox "Incluir mi mejor tiempo en esta ruta" (default: marcado)
             └─ [Empezar] → guard login → permiso background GPS → startSession(...)
```

El botón "Empezar" del modal ejecuta el flujo de arranque que hoy vive en el
`onPressed` del botón de `_buildReady`: `requireAuth`, comprobación de permiso
de background (`LocationService.ensureBackgroundPermission` + diálogo) y
`ctrl.startSession(...)`. El modal se cierra antes de arrancar.

## Componentes

### `SessionConfigSheet` (nuevo widget)

- Se abre con `showModalBottomSheet` (`isScrollControlled: true`), ocupando la
  mayor parte de la pantalla, sobre `LiveSessionScreen`.
- Estado local: `vehicleId`, `name`, `source`, `includeHistorical`.
- Recibe: lista de vehículos del garaje, vehículo por defecto preseleccionado,
  `isAdmin`, `source` inicial, y un callback `onStart(SessionConfig)`.
- Reutiliza `VehiclePickerTile` y el `SegmentedButton<TrackingSource>` que hoy
  están inline en `_buildReady`.
- Devuelve la configuración vía callback; no arranca la sesión por sí mismo.

### `SessionConfig` (objeto de transferencia)

```
class SessionConfig {
  final String? vehicleId;
  final String? name;          // null o vacío => sin nombre
  final TrackingSource source;
  final bool includeHistorical;
}
```

### `_buildReady` (modificado)

Se adelgaza a: título + selector de ruta + mapa de previsualización + banner de
permiso (si aplica) + botón "Comenzar grabación". Se eliminan de aquí el
selector de vehículo, el `SegmentedButton` de telemetría y el hint de fuente
(se mueven al modal). El botón solo abre el `SessionConfigSheet`.

### `LiveSessionController` (modificado)

- `startSession(...)` recibe un nuevo parámetro `bool includeHistorical`.
- `selectVehicle` / fuente se siguen fijando antes de arrancar (los fija el
  flujo del modal a partir del `SessionConfig`).
- Nuevo estado `Duration? _historicalBestLap` con getter público.
- `_loadHistoricalSectorRecords` solo se llama si `includeHistorical == true`;
  en caso contrario `_historicalSectorRecords = const {}`.
- Nuevo `_loadHistoricalBestLap(routeId)`: mínima duración de vuelta **completada**
  entre las sesiones previas de la ruta (`_repo.getSessionsByRoute`). Solo se
  carga si `includeHistorical == true`; null en caso contrario.
- Persistir el nombre: `finishSession` escribe `name` en el `SessionRun`
  guardado (junto al `vehicleId` que ya copia).

## Lógica de comparación

El checkbox controla `includeHistorical`:

- **Marcado** → se cargan `_historicalSectorRecords` (chips morados, como hoy) y
  `_historicalBestLap` (vuelta de referencia).
- **Desmarcado** → ambos vacíos/null: los chips solo reflejan "mejor de la
  sesión"; no hay vuelta de referencia histórica.
- Default: **marcado**.

### Indicador de "Mejor vuelta" (`_LapIndicators`, circuito cerrado)

El indicador derecho muestra la **referencia a batir**:

- `referenceBestLap = includeHistorical && historicalBestLap != null`
  `  ? minNullable(historicalBestLap, sessionBestLap)`
  `  : sessionBestLap`
- Se resalta en color de récord (primary) cuando `referenceBestLap` coincide con
  el récord histórico (aún no batido en la sesión), consistente con el tier
  `overall` de los sectores.
- Si está desmarcado o no hay histórico, se comporta como hoy (mejor vuelta de la
  sesión).

`_LapIndicators` recibe los nuevos datos (`historicalBestLap`, `includeHistorical`)
desde `_buildRunning`.

### Rutas abiertas

No tienen vueltas, así que el checkbox solo afecta a los chips de sector (el
"fantasma" histórico). El indicador único de cronómetro no cambia.

## Persistencia del nombre

Siguiendo el patrón de `free_rides.name`:

- **Core** (`packages/splitway_core`): añadir `String? name` a `SessionRun`
  (constructor, campos, `copyWith`, serialización JSON si la hay).
- **BD local** (`splitway_local_database.dart`): migración sqflite **v12**:
  `ALTER TABLE session_runs ADD COLUMN name TEXT`. Subir `_schemaVersion` a 12.
- **Repo local** (`local_draft_repository.dart`): mapear `name` al leer/escribir
  `session_runs`.
- **Supabase**: nueva migración en `supabase/migrations/` →
  `ALTER TABLE sessions ADD COLUMN name text;` y actualizar la función
  `upsert_session_with_telemetry` (variante de params uuid, ver
  `20260614000000_session_upsert_uuid_params.sql`) para aceptar y escribir `name`.
- **Sync** (`sync_service.dart` / `supabase_repository.dart`): incluir `name` en
  el payload de upsert y al hidratar sesiones remotas.
- **Historial**: mostrar el nombre en la lista/detalle de sesiones cuando exista
  (fallback al nombre de la ruta cuando es null/vacío).

## Localización

Nuevas cadenas en `app_es.arb` / `app_en.arb` (y regenerar
`app_localizations*.dart`):

- Título del modal de configuración.
- Etiqueta y campo del nombre opcional.
- Etiqueta + texto explicativo del checkbox "Incluir mi mejor tiempo en esta ruta".
- Botón "Empezar" del modal.
- Etiqueta de la "vuelta de referencia" si difiere de la actual.

## Testing

- **Controller**: `includeHistorical=false` deja `historicalSectorRecords` vacío
  y `historicalBestLap` null; `true` los carga.
- **Best lap histórico**: `_loadHistoricalBestLap` devuelve la mínima vuelta
  **completada** (ignora vueltas incompletas) y null sin historial.
- **`SessionConfigSheet`** (widget): aparece tras pulsar el botón; muestra
  vehículo, nombre y checkbox; la fuente de telemetría solo si admin; el checkbox
  arranca marcado; "Empezar" devuelve el `SessionConfig` esperado.
- **Persistencia del nombre**: round-trip en `local_draft_repository`
  (guardar con nombre → leer → coincide; null se conserva null).
- **`_LapIndicators`**: con histórico incluido muestra la referencia a batir y el
  resaltado de récord; sin histórico se comporta como hoy.

## Fuera de alcance

- Mostrar deltas en vivo contra cada sector histórico más allá del coloreado
  actual de los chips.
- Comparación contra sesiones de **otros** usuarios (esto es solo el mejor del
  propio usuario).
- Editar el nombre de una sesión a posteriori desde el historial.
