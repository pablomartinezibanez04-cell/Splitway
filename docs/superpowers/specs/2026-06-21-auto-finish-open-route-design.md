# Auto-finalización de sesión al acabar una ruta abierta

**Fecha:** 2026-06-21
**Estado:** Aprobado (diseño)

## Resumen

Cuando el corredor llega al final de una **ruta abierta**, la sesión debe
terminarse automáticamente: parar el cronómetro, guardar el run y mostrar la
pantalla de resultados, sin que el usuario tenga que pulsar "Finalizar".

Las **rutas cerradas** ya cierran la vuelta al cruzar la línea de meta y arrancan
la siguiente automáticamente — ese comportamiento **no cambia**.

## Contexto / estado actual

El motor de tracking (`packages/splitway_core/lib/src/tracking/tracking_engine.dart`)
ya detecta el final de una ruta abierta:

- `_finishOpenRoute()` se dispara cuando un punto ingerido está a ≤20 m
  (`_finishProximityMeters`) del último punto del trazado, en una ruta con
  `isClosed == false` y estado `inLap`.
- Pone el estado del motor en `finished` y emite el evento `TrackingFinished`.

**El hueco:** ni `LiveTrackingController` ni `LiveSessionController` reaccionan a
`TrackingFinished`. Resultado: en una ruta abierta, al llegar al final el motor
deja de registrar puntos internamente, pero la UI sigue en estado `running` con
el cronómetro de vuelta corriendo indefinidamente. El usuario tiene que pulsar
"Finalizar" a mano.

Para rutas cerradas el motor nunca emite `TrackingFinished` de forma automática
(solo en `finish()` manual): cada cruce de la línea de meta cierra una vuelta y
abre la siguiente. Ese flujo es correcto y se mantiene.

## Solución

Conectar el evento `TrackingFinished` que ya existe, a través de las tres capas.

### 1. `LiveTrackingController` (`movile_app/lib/src/services/tracking/live_tracking_controller.dart`)

En la suscripción existente a los eventos del motor (`_eventSub`), al recibir un
evento `TrackingFinished`:

- Cambiar `_state` a `LiveControllerState.finished`.
- Cancelar el ticker de 100 ms (`_ticker`).
- `notifyListeners()`.

Hoy `_state` solo pasa a `finished` desde `finishSession()` (manual). `finishSession()`
ya es idempotente cuando el estado es `finished` (devuelve `_engine.finish()`), así
que una llamada posterior sigue funcionando.

### 2. `LiveSessionController` (`movile_app/lib/src/features/session/live_session_controller.dart`)

En `_onTrackerChange` (ya es listener del tracker): si el `_stage` es `running` o
`paused` y el tracker está en `LiveControllerState.finished`, disparar el flujo de
auto-finalización, que reutiliza `finishSession()` (cancela GPS, para background,
guarda el run vía repo, pasa `_stage` a `finished`, notifica).

- Guard `_autoFinishing` (bool) para evitar que se dispare dos veces mientras el
  `await` de `finishSession()` está en curso.
- `finishSession()` es `async`; `_onTrackerChange` es síncrono, así que se lanza
  sin esperar (fire-and-forget) protegido por el guard.

### 3. `LiveSessionScreen` (`movile_app/lib/src/features/session/live_session_screen.dart`)

Mover el snackbar de "sesión guardada" del callback `onFinish` del botón a la
detección de transición de stage en `_onChange`:

- Cuando `_prevStage` es `running` o `paused` y el nuevo stage es `finished`,
  mostrar `l.sessionSavedSnackBar`.
- Quitar el snackbar del `onFinish` del botón para no duplicarlo.

Así el mensaje aparece igual en finalización manual y automática, desde un único
sitio.

## Lo que NO cambia

- El motor de tracking (`tracking_engine.dart`): ya emite `TrackingFinished` y
  detecta proximidad; no se modifica.
- La lógica de rutas cerradas (bucle de vueltas).
- El umbral de proximidad (≤20 m al último punto del trazado).

## Flujo resultante (ruta abierta)

1. El corredor llega a ≤20 m del último punto → motor emite `TrackingFinished`.
2. `LiveTrackingController` pasa a `finished`, cancela su ticker, notifica.
3. `LiveSessionController._onTrackerChange` detecta tracker `finished` con stage
   `running`/`paused` → llama a `finishSession()`.
4. `finishSession()` cancela GPS/background, guarda el run, `_stage = finished`.
5. `LiveSessionScreen` reconstruye en `_buildFinished` y muestra el snackbar.

## Tests (TDD)

- **`LiveTrackingController`**: ingerir una secuencia de puntos que termina cerca
  del último punto de una ruta abierta → `state` pasa a `finished` por sí solo
  (sin llamar a `finishSession()`).
- **`LiveSessionController`**: misma situación → `stage` pasa a `finished` y el run
  queda guardado en el repo, sin invocar el botón "Finalizar". Verificar que el
  guard evita doble guardado.
- **Ruta cerrada (regresión)**: ingerir puntos que completan una vuelta y siguen →
  la sesión NO auto-finaliza; sigue en `running` y abre la siguiente vuelta.
