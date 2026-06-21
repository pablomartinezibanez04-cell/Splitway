# Recorte de estela + overlay de finalización en rutas abiertas

**Fecha:** 2026-06-21
**Estado:** Aprobado (diseño)

## Resumen

Tres cambios encadenados que mejoran la experiencia de una **ruta abierta**:

1. **Recorte de la estela**: la estela del coche solo se dibuja (y se guarda en el
   historial) entre el cruce del **primer nodo** y el final de la ruta. Antes de
   empezar y después de terminar no se dibuja nada.
2. **Tiempo de referencia**: una duración de referencia (su mejor marca previa o el
   tiempo normal de la ruta) que se muestra tanto **durante** la carrera como en el
   resumen final.
3. **Overlay de finalización**: al terminar una ruta abierta no se salta
   instantáneamente a la pantalla de resultados; aparece un overlay semi-transparente
   con el tiempo y la mejora/empeora respecto a la referencia, y un botón "Continuar".
   El mapa con la estela y los controles inferiores quedan congelados.

Las **rutas cerradas** mantienen su flujo actual (vueltas, current/best lap, fin
manual → resultados). Solo el punto 1 (recorte de inicio de estela) aplica también a
cerradas, por coherencia.

## Contexto / estado actual

- La estela se dibuja desde puntos de telemetría (`TelemetryPoint`). El motor
  (`packages/splitway_core/lib/src/tracking/tracking_engine.dart`) distingue estados
  `idle` → `awaitingStart` → `inLap` → `finished`.
- **Inicio (bug):** en `TrackingEngine.ingest`, `_points.add(point)` es
  incondicional mientras el estado no sea `idle`/`finished`, así que **se guardan
  puntos durante `awaitingStart`** (antes de cruzar el primer nodo). La vista en vivo
  dibuja `tracker.ingested` (todos los puntos), así que la estela aparece antes de
  empezar y queda en el historial guardado.
- **Final:** la auto-finalización ya está cableada (commits `7551fab`, `15ba600`,
  `ec18516`): cuando un punto llega a ≤20 m del último punto del trazado, el motor
  emite `TrackingFinished`, `LiveTrackingController` pasa a `finished` y
  `LiveSessionController._onTrackerChange` llama a `finishSession()`, que cancela el
  GPS, guarda el run y pone `_stage = finished` → la pantalla salta a `_buildFinished`.
  Ese salto instantáneo es lo que se sustituye por el overlay.
- Datos existentes reutilizables:
  - `RouteTemplate.expectedDuration` (`Duration?`): tiempo normal de la ruta.
  - `LiveSessionController.includeHistorical` (bool): el usuario eligió "correr contra
    su mejor marca" en el modal de configuración.
  - `LiveSessionController` ya carga histórico en `startSession`
    (`_historicalBestLap`, `_historicalSectorRecords`) vía `_repo.getSessionsByRoute`.
  - `TimeDeltaIndicator(expected, actual)` (`movile_app/lib/src/shared/widgets/time_delta_indicator.dart`):
    muestra el % más rápido/lento con flecha verde/roja.
  - `SessionRun.totalDuration` (`endedAt - startedAt`): tiempo total del run.

## Parte 1 — Recorte de la estela

### Motor (`tracking_engine.dart`)
- Sustituir el `_points.add(point)` incondicional por un guard: registrar el punto
  **solo cuando `_status == TrackingStatus.inLap`**. Resultado:
  - Puntos en `awaitingStart` (antes del primer nodo) → no se guardan.
  - El punto que cruza el primer nodo abre `inLap` *después* del guard, así que la
    estela empieza ~1 muestra después del nodo (diferencia imperceptible, a metros del
    nodo).
  - El punto que dispara `_finishOpenRoute` se guarda (en ese `ingest` el estado aún
    es `inLap` al llegar al guard); los siguientes ya no (estado `finished`).
- Exponer un getter público `List<TelemetryPoint> get recordedPoints =>
  List.unmodifiable(_points);` para que la vista en vivo dibuje el mismo tramo que se
  persiste.
- Efecto en stats: `_totalDistanceMeters`/`_maxSpeedMps` siguen acumulándose como hoy
  (no se tocan). `avgSpeed` se calcula sobre `_points.first/last.timestamp`, que ahora
  corresponden al tramo de ruta — ligeramente más correcto. Aceptado.

### Controlador en vivo (`live_tracking_controller.dart`)
- Añadir `List<TelemetryPoint> get trailPoints => _engine.recordedPoints;`.
- `ingested` se mantiene tal cual (todos los puntos) para marcador, cámara y rumbo.

### Pantalla (`live_session_screen.dart`)
- En `_buildRunning`, la `SplitwayMap` pasa a `telemetry: tracker.trailPoints` (en vez
  de `tracker.ingested`). `userLocation` sigue usando `tracker.ingested.last`.

### Mapa (`splitway_map.dart`)
- Añadir parámetro `bool recording` (default `true`, no cambia a los demás llamadores).
- Definir `bool get _growsTip => _animatedUserLocation != null && widget.recording;` y
  usarlo donde hoy se usa `_hasLivePosition` para decidir el split línea estática/tip
  (`_renderAnnotationsCore`) y en `showTip` de `_ensureTelemetryTipCore`.
- `didUpdateWidget`: incluir `oldWidget.recording != widget.recording` en
  `annotationsChanged` para re-renderizar al congelar.
- La vista en vivo pasa `recording: tracker.snapshot.status == TrackingStatus.inLap`.
  Así, tras finalizar (estado `finished`) el tip deja de crecer y la línea queda
  estática en el último punto del tramo, aunque llegue alguna muestra rezagada.

## Parte 2 — Tiempo de referencia

### Controlador (`live_session_controller.dart`)
- Nuevo campo `Duration? _historicalBestTotal` + getter, cargado en `startSession`
  (cuando `includeHistorical`) como el **mínimo `totalDuration`** entre las sesiones
  previas de rutas **abiertas** del usuario en esa ruta (sesiones completadas con
  `totalDuration != null`). Null si no hay ninguna.
- Nuevo getter derivado:
  ```dart
  Duration? get referenceDuration {
    if (_includeHistorical && _historicalBestTotal != null) {
      return _historicalBestTotal;
    }
    return _selected?.expectedDuration;
  }
  ```
  (Si eligió competir pero es su primera vez → cae a `expectedDuration`. Si no eligió →
  `expectedDuration`.)

### Indicador en vivo (`_LapIndicators`, rutas abiertas)
- Hoy las rutas abiertas muestran un único cronómetro centrado. Cambiar a un layout de
  dos columnas (como el de circuito cerrado): izquierda = tiempo transcurrido
  (`snapshot.currentLapElapsed`), derecha = **objetivo** (`referenceDuration`
  formateado, o un placeholder si es null).
- Pasar `referenceDuration` a `_LapIndicators` desde `_buildRunning`.

## Parte 3 — Overlay de finalización (solo rutas abiertas)

### Estado intermedio
- Nuevo valor `LiveSessionStage.summary` entre `running` y `finished`.
- `finishSession()` guarda el run igual, pero el `_stage` resultante depende:
  - Ruta **abierta** → `_stage = LiveSessionStage.summary`.
  - Ruta **cerrada** (o sin overlay) → `_stage = LiveSessionStage.finished` (igual que hoy).
- Nuevo método `void dismissFinishOverlay()` → `_stage = LiveSessionStage.finished;
  notifyListeners();` (lo llama el botón "Continuar").
- `resetForNewSession` ya cubre la limpieza; no se añade estado persistente extra.

### Pantalla
- En el `switch (ctrl.stage)` de `build`: `LiveSessionStage.summary => _buildRunning(...)`
  (mismo método, así la `SplitwayMap` se mantiene montada y la estela no re-encuadra).
- En `_buildRunning`, cuando `ctrl.stage == summary`:
  - El mapa se mantiene con la estela congelada (`recording: false`, ya que el estado
    del tracker es `finished`).
  - Los controles inferiores (GPS badge, cronómetro, botones pausa/finalizar) quedan
    **congelados**: no tickean (el `_uiTicker` solo hace `setState` en `running`, y el
    ticker del tracker ya está cancelado en `finished`).
  - Se añade un layer `Positioned.fill` con el **overlay**: un panel centrado con fondo
    semi-transparente (p. ej. `surface.withValues(alpha: 0.85)` sobre un velo
    `Colors.black.withValues(alpha: 0.25)`), con:
    - Título "Ruta finalizada".
    - Tiempo total (`_result.totalDuration` formateado en HMS).
    - `TimeDeltaIndicator(expected: referenceDuration, actual: totalDuration)` cuando
      `referenceDuration != null`; si es null, no se muestra delta.
    - Botón `FilledButton` "Continuar" → `ctrl.dismissFinishOverlay()`.
- Al pulsar "Continuar": `_stage = finished` → rebuild → `_buildFinished` (pantalla de
  resultados existente).

### Finalización manual de ruta abierta
- Si el usuario pulsa "Finalizar" en una ruta abierta antes de llegar al final, también
  pasa por `summary` (coherente: mismo overlay). El tiempo y delta se calculan igual.

### Snackbar
- El snackbar "sesión guardada" del botón `onFinish` se mantiene solo en la
  finalización manual. En la auto-finalización no se muestra snackbar: el overlay ya es
  el feedback de que la ruta terminó y se guardó. No se mueve la lógica del snackbar.

## l10n
Nuevas claves (con sus traducciones es/en): título "Ruta finalizada", etiqueta
"Objetivo" para el indicador en vivo, y "Continuar" para el botón. Reutilizar las
existentes donde sea posible (`sessionElapsedLabel`, formatos de `Formatters`).

## Lo que NO cambia
- Motor: detección de cruces, proximidad (≤20 m), lógica de vueltas de rutas cerradas.
- Flujo de rutas cerradas (current/best lap, fin manual → resultados).
- Acumuladores de distancia/velocidad máxima.
- Sesiones ya guardadas en el historial (el recorte aplica solo a grabaciones nuevas).

## Tests (TDD)
- **Motor**: ingerir puntos antes de cruzar el primer nodo + después → `recordedPoints`
  solo contiene el tramo `inLap` (excluye pre-inicio); el punto de finalización por
  proximidad sí está incluido; los posteriores no.
- **`LiveSessionController`**:
  - `referenceDuration` = mejor total previo cuando `includeHistorical` y hay histórico;
    = `expectedDuration` cuando no eligió o no hay histórico.
  - Auto-finalización de ruta abierta → `stage == summary` (no `finished`) y run guardado;
    `dismissFinishOverlay()` → `stage == finished`.
  - Ruta cerrada (regresión): completar vuelta y seguir → no auto-finaliza, sigue en
    `running`.
- **Widget** (`live_session_screen`): en `summary`, se muestra el overlay con tiempo y
  botón "Continuar"; al pulsarlo se renderiza `_buildFinished`.
