# Auto-finalización de sesión al acabar una ruta abierta — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cuando el corredor llega al final de una ruta abierta, la sesión se finaliza sola (para el cronómetro, guarda el run y muestra resultados) sin pulsar "Finalizar". Las rutas cerradas siguen igual.

**Architecture:** El motor de tracking ya emite `TrackingFinished` por proximidad al último punto en rutas abiertas. Conectamos ese evento que ya existe a través de dos controllers: `LiveTrackingController` pasa su estado a `finished` al recibir el evento, y `LiveSessionController` lo detecta y reutiliza su `finishSession()`. La pantalla muestra el snackbar de "guardado" desde un único sitio (la transición de stage) para cubrir finalización manual y automática.

**Tech Stack:** Flutter / Dart, paquete `splitway_core` (motor de tracking), `flutter_test`, `sqflite_common_ffi` (repo en memoria para tests).

---

## File Structure

- `movile_app/lib/src/services/tracking/live_tracking_controller.dart` — reaccionar a `TrackingFinished` (estado → finished, cancelar ticker).
- `movile_app/lib/src/features/session/live_session_controller.dart` — detectar tracker finalizado y auto-finalizar la sesión; guard anti-doble-disparo; reset del guard.
- `movile_app/lib/src/features/session/live_session_screen.dart` — mover el snackbar de "guardado" a la transición de stage.
- `movile_app/test/services/tracking/live_tracking_controller_test.dart` — tests del auto-finish del tracker y regresión de ruta cerrada.
- `movile_app/test/features/session/live_session_controller_test.dart` — test de auto-finalización de la sesión.

**Nota de ejecución:** todos los comandos `flutter test` / `flutter analyze` se ejecutan desde el directorio `movile_app/`.

---

## Task 1: `LiveTrackingController` se auto-finaliza al recibir `TrackingFinished`

**Files:**
- Modify: `movile_app/lib/src/services/tracking/live_tracking_controller.dart`
- Test: `movile_app/test/services/tracking/live_tracking_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

Añade al final del fichero de test, justo antes del cierre `}` de `main()` (después del grupo `buildAutoLapScript`). Añade también el helper `_tp` y un helper `_closedRoute` al principio del fichero (junto a `_straightRoute`).

Helper `_tp` y `_closedRoute` (pegar tras la definición de `_straightRoute`, antes de `final _uuidRe`):

```dart
TelemetryPoint _tp(double lat, double lon, DateTime t) => TelemetryPoint(
      timestamp: t,
      location: GeoPoint(latitude: lat, longitude: lon),
      speedMps: 12,
    );

/// Triángulo cerrado (path.first == path.last) con la puerta de meta sobre
/// path[0], perpendicular al primer tramo.
RouteTemplate _closedRoute() {
  const start = GeoPoint(latitude: 40.0, longitude: -3.0);
  final path = const [
    start,
    GeoPoint(latitude: 40.0005, longitude: -3.0),
    GeoPoint(latitude: 40.0005, longitude: -2.9994),
    start, // cierre: last == first → isClosed == true
  ];
  const gate = GateDefinition(
    left: GeoPoint(latitude: 40.0, longitude: -3.0001),
    right: GeoPoint(latitude: 40.0, longitude: -2.9999),
  );
  return RouteTemplate(
    id: 'closed-route',
    name: 'Closed route',
    path: path,
    startFinishGate: gate,
    sectors: const [],
    difficulty: RouteDifficulty.easy,
    createdAt: DateTime(2026),
  );
}
```

Grupo de tests nuevo (pegar antes del cierre de `main()`):

```dart
  group('auto-finish on TrackingFinished', () {
    final base = DateTime(2026, 5, 9, 10);

    test('open route auto-finishes when the end is reached', () async {
      // 5-point straight open route; last point at lat 40.00036 (~40 m from
      // the gate). Using 5 points keeps the gate-crossing point well outside
      // the 20 m finish-proximity of the last path point, so the run does not
      // finish prematurely on the crossing.
      final route = _straightRoute(pointCount: 5);
      final controller = LiveTrackingController(route: route);
      controller.startSession();

      // South of the gate (baseline).
      controller.ingestSimulatedPoint(_tp(39.9999, -3.0, base));
      // Cross the start gate (north) → lap begins. ~34 m from the end.
      controller.ingestSimulatedPoint(
          _tp(40.00005, -3.0, base.add(const Duration(seconds: 1))));
      // Reach the last path point (40.00036, -3.0) → proximity finish.
      controller.ingestSimulatedPoint(
          _tp(40.00036, -3.0, base.add(const Duration(seconds: 2))));

      // Let the engine's broadcast event reach the controller subscription.
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, LiveControllerState.finished);
      controller.dispose();
    });

    test('closed route does NOT auto-finish after completing a lap', () async {
      final route = _closedRoute();
      final controller = LiveTrackingController(route: route);
      controller.startSession();

      // buildAutoLapScript drives one full lap around the closed circuit.
      // intervalMs: 2000 spaces the two gate crossings 4 s apart so the second
      // one clears the engine's 3 s crossing cooldown and actually closes lap 1
      // (opening lap 2) — exercising the loop, not a no-op.
      final script = controller.buildAutoLapScript(
          startTime: base, lapCount: 1, intervalMs: 2000);
      for (final p in script) {
        controller.ingestSimulatedPoint(p);
      }
      await Future<void>.delayed(Duration.zero);

      // Closed circuits loop laps; they never auto-finish on their own.
      expect(controller.state, LiveControllerState.recording);
      controller.dispose();
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/services/tracking/live_tracking_controller_test.dart -n "auto-finish"`
Expected: el test `open route auto-finishes...` FALLA (`state` es `recording`, no `finished`). El test de ruta cerrada PASA ya (no hay regresión todavía).

- [ ] **Step 3: Implement — react to `TrackingFinished` in the event subscription**

En `movile_app/lib/src/services/tracking/live_tracking_controller.dart`, dentro de `startSession()`, sustituye el listener actual:

```dart
    _eventSub = _engine.events.listen((evt) {
      _events.add(evt);
      notifyListeners();
    });
```

por:

```dart
    _eventSub = _engine.events.listen((evt) {
      _events.add(evt);
      // Open routes auto-finish in the engine on proximity to the last path
      // point. Mirror that here so listeners (LiveSessionController) can react.
      if (evt is TrackingFinished && _state == LiveControllerState.recording) {
        _state = LiveControllerState.finished;
        _ticker?.cancel();
        _ticker = null;
      }
      notifyListeners();
    });
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/tracking/live_tracking_controller_test.dart`
Expected: PASS (todo el fichero, incluidos los grupos previos).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/tracking/live_tracking_controller.dart movile_app/test/services/tracking/live_tracking_controller_test.dart
git commit -m "feat: LiveTrackingController auto-finishes on engine TrackingFinished"
```

---

## Task 2: `LiveSessionController` auto-finaliza la sesión al detectar el tracker finalizado

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_controller.dart`
- Test: `movile_app/test/features/session/live_session_controller_test.dart`

- [ ] **Step 1: Write the failing test**

En `movile_app/test/features/session/live_session_controller_test.dart`, añade un helper de ruta abierta y un helper `_tp` tras el helper `route()` existente (dentro de `main`, antes de `seedPriorSession`):

```dart
  TelemetryPoint tp(double lat, double lon, DateTime t) => TelemetryPoint(
        timestamp: t,
        location: GeoPoint(latitude: lat, longitude: lon),
        speedMps: 12,
      );

  RouteTemplate openRoute() => RouteTemplate(
        id: 'r-open',
        name: 'Open',
        path: const [
          GeoPoint(latitude: 40.0, longitude: -3.0),
          GeoPoint(latitude: 40.00018, longitude: -3.0),
          GeoPoint(latitude: 40.00036, longitude: -3.0),
        ],
        startFinishGate: GateDefinition(
          left: GeoPoint(latitude: 40.0, longitude: -3.0001),
          right: GeoPoint(latitude: 40.0, longitude: -2.9999),
        ),
        sectors: const [],
        difficulty: RouteDifficulty.easy,
        createdAt: DateTime.utc(2026, 1, 1),
      );
```

Test nuevo (añadir antes del cierre de `main()`):

```dart
  test('open route auto-finishes the session when the end is reached',
      () async {
    await repo.saveRouteTemplate(openRoute());
    final ctrl =
        LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(openRoute());
    await ctrl.startSession(includeHistorical: false);

    expect(ctrl.stage, LiveSessionStage.running);

    final base = DateTime(2026, 5, 9, 10);
    final t = ctrl.tracker!;
    // South of the gate → cross gate (lap begins, ~34 m from end) → reach the
    // last path point (40.00036). The crossing point stays outside the 20 m
    // finish-proximity so the run does not finish prematurely.
    t.ingestSimulatedPoint(tp(39.9999, -3.0, base));
    t.ingestSimulatedPoint(tp(40.00005, -3.0, base.add(const Duration(seconds: 1))));
    t.ingestSimulatedPoint(tp(40.00036, -3.0, base.add(const Duration(seconds: 2))));

    // Let the engine event propagate to the tracker, then to the session
    // controller, then let the async finishSession() complete (it awaits the
    // repo save).
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(ctrl.stage, LiveSessionStage.finished);
    expect(ctrl.result, isNotNull);
    expect(ctrl.result!.id, t.sessionId);

    // The run was persisted exactly once.
    final saved = await repo.getSessionsByRoute('r-open');
    expect(saved.length, 1);

    ctrl.dispose();
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/session/live_session_controller_test.dart -n "auto-finishes the session"`
Expected: FAIL — `ctrl.stage` sigue en `running` (no hay detección de auto-finish todavía).

- [ ] **Step 3: Implement — guard field, detection in `_onTrackerChange`, reset**

En `movile_app/lib/src/features/session/live_session_controller.dart`:

(a) Añade el campo guard junto a los demás campos de estado (p. ej. tras `bool _backgroundActive = false;` en la línea ~51):

```dart
  /// True while an automatic finish (open route reached its end) is in flight,
  /// so the detection in [_onTrackerChange] does not fire twice during the
  /// async [finishSession] await.
  bool _autoFinishing = false;
```

(b) Sustituye el método `_onTrackerChange` actual:

```dart
  void _onTrackerChange() => notifyListeners();
```

por:

```dart
  void _onTrackerChange() {
    final t = _tracker;
    // Open routes auto-finish in the tracker on proximity to the last path
    // point. When that happens mid-session, finalize the session exactly as
    // the manual "Finish" button would.
    if (t != null &&
        !_autoFinishing &&
        t.state == LiveControllerState.finished &&
        (_stage == LiveSessionStage.running ||
            _stage == LiveSessionStage.paused)) {
      _autoFinishing = true;
      // ignore: discarded_futures
      finishSession();
    }
    notifyListeners();
  }
```

(c) En `resetForNewSession()`, resetea el guard. Añade junto a los demás resets (p. ej. tras `_result = null;`):

```dart
    _autoFinishing = false;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/session/live_session_controller_test.dart`
Expected: PASS (incluidos los tests de historial previos).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_controller.dart movile_app/test/features/session/live_session_controller_test.dart
git commit -m "feat: auto-finish live session when an open route reaches its end"
```

---

## Task 3: `LiveSessionScreen` muestra el snackbar de "guardado" desde la transición de stage

Esto unifica el mensaje "sesión guardada" para finalización manual y automática, evitando duplicarlo. No se añade test automatizado (el snackbar requiere un widget test pesado); se verifica con la suite existente + `flutter analyze` + comprobación manual del flujo.

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`

- [ ] **Step 1: Mostrar el snackbar al detectar la transición a `finished` en `_onChange`**

En `movile_app/lib/src/features/session/live_session_screen.dart`, en el método `_onChange`, localiza este bloque (líneas ~189):

```dart
    _prevStage = ctrl.stage;
```

Justo ANTES de esa línea, inserta la detección de transición:

```dart
    // Show the "session saved" snackbar once when the session finishes —
    // covers both the manual Finish button and the automatic open-route finish.
    if (ctrl.stage == LiveSessionStage.finished &&
        _prevStage != null &&
        _prevStage != LiveSessionStage.finished &&
        ctrl.result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).sessionSavedSnackBar)),
      );
    }
    _prevStage = ctrl.stage;
```

- [ ] **Step 2: Quitar el snackbar del botón "Finalizar" para no duplicarlo**

En el mismo fichero, en `_buildRunning`, localiza el callback `onFinish` (líneas ~590):

```dart
                        onFinish: () async {
                          final savedText = l.sessionSavedSnackBar;
                          final messenger = ScaffoldMessenger.of(context);
                          final session = await ctrl.finishSession();
                          if (!mounted || session == null) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(savedText)),
                          );
                        },
```

Sustitúyelo por (el snackbar ahora lo dispara `_onChange` en la transición de stage):

```dart
                        onFinish: () async {
                          await ctrl.finishSession();
                        },
```

- [ ] **Step 3: Analyze + full test suite**

Run: `flutter analyze`
Expected: sin errores nuevos (ojo a `l` sin usar en `_buildRunning` — si el analizador marca `l` como no usado, comprueba que sigue usándose en el resto del método; en este fichero `l` se usa en múltiples sitios, así que debe seguir referenciado).

Run: `flutter test`
Expected: PASS (toda la suite del módulo móvil).

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart
git commit -m "refactor: show session-saved snackbar from stage transition (manual + auto finish)"
```

---

## Verification final

- [ ] **Suite completa del core** (no se modifica, pero confirmamos que no hay regresión):

Run (desde la raíz del repo): `cd packages/splitway_core && flutter test` (o `dart test` según el setup del paquete)
Expected: PASS.

- [ ] **Comprobación manual del flujo (ruta abierta):** iniciar una sesión en una ruta abierta en modo simulado, usar "Auto" hasta que el recorrido llegue al final → la sesión debe pasar sola a la pantalla de resultados y mostrarse el snackbar "sesión guardada".

- [ ] **Comprobación manual (ruta cerrada):** iniciar una ruta cerrada en simulado → al completar una vuelta debe abrir la siguiente y NO finalizar la sesión.
