# Ruta Demo Jarama + Tombstone — Diseño

**Fecha:** 2026-05-23

---

## 1. Objetivo

Dos cambios independientes pero relacionados con la ruta demo que se precarga al instalar la app:

1. **Cambiar la ruta demo** del óvalo ficticio centrado en Madrid al trazado aproximado del Circuito del Jarama (San Sebastián de los Reyes, Madrid).
2. **Tombstone**: si el usuario borra la ruta demo, no volver a sembrarla en el siguiente inicio de app.

---

## 2. Nueva ruta demo — Circuito del Jarama

| Campo | Valor |
|---|---|
| ID | `'demo-jarama'` |
| Nombre | `'Circuito del Jarama'` |
| Descripción | Trazado aproximado del Circuito del Jarama (San Sebastián de los Reyes, Madrid). |
| Ubicación | ~40.62°N, ~3.59°W |
| Waypoints | ~21 puntos GPS que aproximan el trazado real |
| Sectores | 2: Sector 1 (salida del chicane), Sector 2 (antes del chicane final) |
| Dificultad | `RouteDifficulty.hard` |

**Nota sobre usuarios existentes:** los que ya tienen `'demo-oval'` en su BD no pierden nada — la ruta antigua permanece intacta. Solo los nuevos installs (o usuarios que hayan borrado la oval) ven la Jarama. No hay migración de BD.

---

## 3. Tombstone via SharedPreferences

### Clave de almacenamiento

`AppSettingsController` añade:
- `static const _kDismissedDemoIds = 'dismissed_demo_route_ids'`
- `Set<String> get dismissedDemoIds` — lee la lista de SharedPreferences como `Set<String>`
- `Future<void> dismissDemoRoute(String id)` — añade `id` al set

### Flujo de borrado individual (RouteEditorController)

```
route_detail_screen.dart
  → widget.controller.deleteRoute(route.id)
    → RouteEditorController.deleteRoute(id)
      → (elimina de BD / sync)
      → onRouteDeleted?.call(id)
        → settingsController.dismissDemoRoute(id)
          → SharedPreferences.setStringList('dismissed_demo_route_ids', [...])
```

### Flujo de borrado masivo (SettingsScreen._clearCache)

`_clearCache` llama `repository.deleteRoute(r.id)` directamente (sin pasar por `RouteEditorController`), por lo que también debe llamar `settingsController.dismissDemoRoute(r.id)` para cada ruta.

### Arranque de app (main.dart → DemoSeed.ensureSeeded)

```
main()
  → settingsController = await AppSettingsController.load()  ← movido antes del seed
  → DemoSeed.ensureSeeded(repo, settings)
    → settings.dismissedDemoIds.contains('demo-jarama') ?
        sí → return (no siembra)
        no → comprobar si ya existe en BD → si no, sembrar
```

---

## 4. Archivos afectados

| Archivo | Cambio |
|---|---|
| `lib/src/services/settings/app_settings_controller.dart` | `dismissedDemoIds` + `dismissDemoRoute()` |
| `lib/src/data/demo/demo_seed.dart` | Ruta Jarama + tombstone en `ensureSeeded()` |
| `lib/main.dart` | Cargar settings antes de sembrar; pasar settings |
| `lib/src/features/editor/route_editor_controller.dart` | Param `onRouteDeleted` + llamada en `deleteRoute()` |
| `lib/src/routing/app_router.dart` | Pasar `onRouteDeleted: settingsController.dismissDemoRoute` |
| `lib/src/features/settings/settings_screen.dart` | `_clearCache()` llama `dismissDemoRoute` por cada ruta |

---

## 5. Tests nuevos / modificados

| Archivo de test | Qué verifica |
|---|---|
| `test/services/settings/app_settings_controller_test.dart` | `dismissedDemoIds` vacío por defecto, persiste tras recarga, idempotente |
| `test/data/demo/demo_seed_test.dart` (nuevo) | Siembra Jarama en BD vacía; no re-siembra si ya existe; no siembra si dismisseado; no re-siembra tras borrado+dismiss |
| `test/features/editor/route_editor_controller_test.dart` | Callback `onRouteDeleted` se invoca al borrar una ruta |
