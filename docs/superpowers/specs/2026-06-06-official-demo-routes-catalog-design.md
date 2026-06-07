# Catálogo de rutas oficiales de demostración

**Fecha**: 2026-06-06
**Estado**: Diseño aprobado

## Objetivo

Sustituir la actual ruta demo hardcoded (`demo-espana` en `DemoSeed`) por un catálogo dinámico de rutas oficiales de Splitway servido desde Supabase. Las rutas oficiales:

- Pertenecen al usuario `splitwayoficial@gmail.com`.
- Son visibles en el dispositivo desde el primer arranque, sin necesidad de iniciar sesión.
- Se descargan desde Supabase (no están hardcoded en el binario), permitiendo modificarlas o añadir nuevas sin redeploy.
- Persisten en el dispositivo hasta que el usuario (autenticado o no) las descarta.
- Una vez descartadas no reaparecen, salvo que: (a) Splitway publique una ruta oficial nueva (ID distinto), o (b) la ruta descartada sea modificada en Supabase (`updated_at` posterior al momento de descarte).
- Nunca se convierten en propiedad del usuario autenticado.

## No objetivos

- Sincronizar el estado de descarte entre dispositivos. Cada dispositivo lleva su propia lista de descartes locales. Si el usuario inicia sesión en un dispositivo nuevo, verá las demos hasta que las descarte allí también.
- Tabla nueva en Supabase para descartes — se mantiene todo en local.
- Edge Functions o servicios intermedios — se usa la anon key de Supabase con RLS abierta a lectura.

## Modelo de datos

### Supabase — tabla `route_templates`

La columna `is_official BOOLEAN` ya existe. Se añaden:

```sql
-- Lectura pública (anon + authenticated) de cualquier ruta marcada oficial.
CREATE POLICY "official_routes_public_read" ON route_templates
  FOR SELECT TO anon, authenticated
  USING (is_official = true);

-- Trigger de salvaguarda: solo el dueño splitwayoficial puede crear o marcar
-- rutas oficiales. El UUID se hardcodea en la migración SQL, no en la app.
CREATE OR REPLACE FUNCTION enforce_official_owner()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_official = true AND NEW.owner_id <> '<UUID_SPLITWAYOFICIAL>' THEN
    RAISE EXCEPTION 'Only the Splitway official account can publish official routes';
  END IF;
  RETURN NEW;
END$$;

CREATE TRIGGER enforce_official_owner_trg
  BEFORE INSERT OR UPDATE ON route_templates
  FOR EACH ROW EXECUTE FUNCTION enforce_official_owner();
```

La policy `SELECT` solo concede lectura. INSERT, UPDATE y DELETE siguen restringidos por las policies de propietario existentes — únicamente la cuenta de Splitway puede modificar sus propias rutas, y el trigger impide marcarlas oficiales desde cualquier otra cuenta.

La policy `SELECT` para anon convive con la policy existente para `authenticated` (que filtra por `owner_id = auth.uid()`). Un usuario autenticado obtendrá la unión: sus propias rutas más las oficiales.

La tabla `sectors` necesita la misma apertura para lectura anónima cuando el `route_id` es de una ruta oficial:

```sql
CREATE POLICY "official_sectors_public_read" ON sectors
  FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM route_templates rt
    WHERE rt.id = sectors.route_id AND rt.is_official = true
  ));
```

### SQLite local — tabla `route_templates`

Migración (nueva versión del esquema en `splitway_local_database.dart`):

```sql
ALTER TABLE route_templates ADD COLUMN is_official INTEGER NOT NULL DEFAULT 0;
ALTER TABLE route_templates ADD COLUMN updated_at INTEGER;  -- millis UTC
```

Convenciones:

- Una ruta oficial se almacena con `owner_id IS NULL AND is_official = 1 AND updated_at = <timestamp remoto>`.
- Una ruta de usuario nunca puede tener `is_official = 1`. El upsert del repositorio enforcea esta invariante.
- El filtro de visibilidad existente — `owner_id IS NULL OR owner_id = ?` — sigue funcionando: anónimo ve solo oficiales, autenticado ve sus propias rutas más oficiales.

### Modelo `RouteTemplate` (paquete `splitway_core`)

Se añaden dos campos:

```dart
class RouteTemplate {
  // ... campos existentes ...
  final bool isOfficial;
  final DateTime? updatedAt;
}
```

`isOfficial` por defecto `false`. `updatedAt` puede ser null para rutas locales aún no sincronizadas con Supabase.

### Settings — descartes locales

Se reemplaza la API actual `Set<String> dismissedDemoIds` por:

```dart
Map<String, int> get dismissedOfficialRoutes;   // routeId -> updated_at millis al descartar
Future<void> recordDismissal(String routeId, int updatedAtMillis);
Future<void> clearDismissal(String routeId);
```

Migración (corre una vez en `AppSettingsController.initialize`):

```dart
if (prefs.containsKey('dismissed_demo_route_ids')) {
  final legacy = prefs.getStringList('dismissed_demo_route_ids') ?? [];
  final migrated = { for (final id in legacy) id: 0 };  // 0 = epoch
  await prefs.setString('dismissed_official_routes', jsonEncode(migrated));
  await prefs.remove('dismissed_demo_route_ids');
}
```

Cualquier `updated_at` real de Supabase es > 0, así que las descartadas legacy reaparecen la primera vez que se haga un fetch. Esto es consistente con la regla "si se modifica reaparece": al no tener un timestamp de descarte real, asumimos lo más conservador para el usuario.

## Servicio `OfficialRoutesService`

Nueva clase en `lib/src/services/official_routes/official_routes_service.dart`, independiente de `SyncService` (que solo se ejecuta cuando hay sesión).

### Responsabilidades

1. **Fetch** desde Supabase: `SELECT * FROM route_templates WHERE is_official = true` más sus `sectors`. Usa la anon key — funciona tanto si el usuario está autenticado como si no.
2. **Reconciliación**:
   - **Upsert** cada ruta oficial remota en local con `owner_id = NULL`, `is_official = 1`, `updated_at = remote.updated_at`.
   - **Prune**: borrar de local cualquier ruta con `is_official = 1` cuyo ID no aparezca en la respuesta remota (caso "Splitway despublicó o borró").
3. **Aplicación de descartes**: tras el upsert, para cada `(routeId, dismissedAt)` en `dismissedOfficialRoutes`:
   - Si `remote.updated_at > dismissedAt`: quitar del map y dejar la ruta visible en local (reaparece).
   - En caso contrario: eliminar la ruta del local (sigue descartada).

### Interfaz pública

```dart
class OfficialRoutesService {
  OfficialRoutesService({
    required SupabaseClient client,
    required LocalDraftRepository local,
    required AppSettingsController settings,
  });

  Future<void> refresh();                  // fetch + reconciliación
  Future<void> dismiss(String routeId);    // borra local + registra updatedAt en settings
}
```

`dismiss(id)` lee el `updated_at` actual de la ruta en local, lo persiste vía `settings.recordDismissal`, y borra la ruta del local.

### Concurrencia

Un flag interno `_isFetching` evita refrescos solapados. Llamadas concurrentes mientras hay una en vuelo se descartan silenciosamente (no se encolan).

### Fallo de red / offline

`refresh()` captura excepciones de red/Supabase, emite un log de warning vía `AppLogger`, y no propaga el error. El usuario sigue viendo el estado actual del local. El próximo trigger reintenta.

En el primer arranque sin red de un dispositivo nuevo, la lista de demos estará vacía. Es comportamiento aceptado.

### Triggers de `refresh()`

| Trigger | Quién lo dispara |
|---|---|
| Cold start | `main.dart` tras `Supabase.initialize`, en background sin bloquear el primer frame |
| Pull-to-refresh en la lista de rutas | El controlador de la pantalla de rutas |
| Login exitoso | `AuthService.signIn` y `signUp`, tras `clearUserData()` |
| Logout exitoso | `AuthService.signOut`, tras `clearUserData()` |

## Cambios en código existente

### Eliminado

- `lib/src/data/demo/demo_seed.dart` — entero.
- `test/data/demo/demo_seed_test.dart` — entero.
- `LocalDraftRepository._activeDemoId` y todas las referencias literales a `'demo-espana'`.

### Generalizado de "demo-espana" a "cualquier `is_official=1`"

| Localización | Antes | Después |
|---|---|---|
| `LocalDraftRepository.saveRouteTemplate` guardrail | `route.id != _activeDemoId` rechaza cuando `_userId == null` | `!route.isOfficial` rechaza cuando `_userId == null` |
| `LocalDraftRepository.clearUserData` | `WHERE id != 'demo-espana'` | `WHERE is_official = 0` |
| `LocalDraftRepository.purgeLegacyPublicRoutes` | conserva solo `demo-espana` | conserva todas con `is_official = 1` |
| `SyncService` push loop | `if (route.id == 'demo-espana') skip` | `if (route.isOfficial) skip` |
| `SyncService` reconcile/prune | excluye `demo-espana` | excluye todas con `is_official = 1` |

### Wiring nuevo

- **`main.dart`**: instanciar `OfficialRoutesService` tras `Supabase.initialize` y antes de `runApp`. Disparar `service.refresh()` en background (sin `await`) para no retrasar el primer frame.
- **`AuthService`**: tras cada `clearUserData()` en `signIn`/`signUp`/`signOut`, invocar `officialRoutesService.refresh()`. El refresh corre en background y no bloquea la transición.
- **Lista de rutas** (pantalla principal de rutas): añadir o reutilizar `RefreshIndicator` que invoque `service.refresh()`. Si ya existe un pull-to-refresh para otros datos, colgar la llamada del mismo handler.
- **Acción de borrar ruta**: cuando el usuario borra una ruta marcada `isOfficial == true`, redirigir la acción a `officialRoutesService.dismiss(id)` en lugar del `local.deleteRoute(id)` directo. Para rutas de usuario el flujo sigue idéntico.

## Tests

Mínimo de casos a cubrir:

1. `OfficialRoutesService.refresh` inserta rutas nuevas remotas en local con `is_official=1`, `owner_id=NULL`, `updated_at` correctos.
2. `refresh` borra del local rutas oficiales que ya no están en remoto.
3. `refresh` quita de `dismissedOfficialRoutes` una ruta cuyo `updated_at` remoto > `dismissedAt` guardado, y la deja visible.
4. `refresh` borra del local una ruta cuyo `updated_at` remoto ≤ `dismissedAt` guardado (sigue descartada).
5. `dismiss(id)` borra del local y persiste `updated_at` en settings.
6. `LocalDraftRepository.saveRouteTemplate` con `owner_id=null` e `isOfficial=false` falla por assert.
7. `SyncService.push` no sube ninguna ruta con `isOfficial=true` a Supabase.
8. `AuthService.signIn` y `signOut` invocan `OfficialRoutesService.refresh` tras `clearUserData`.
9. Migración de settings: `Set<String>` legacy → `Map<String,int>` con valores 0; tras un refresh con remoto > 0 los IDs migrados reaparecen.
10. Una ruta de usuario autenticado que se intenta marcar `isOfficial=true` en Supabase falla por el trigger `enforce_official_owner`.

## Riesgos y mitigaciones

- **Anon key expuesta**: la anon key vive en el binario y se puede extraer; aceptable porque las rutas oficiales son por definición públicas y la policy solo permite SELECT sobre `is_official = true`.
- **Trigger SQL bloquea promociones legítimas**: si en el futuro Splitway necesita rotar de cuenta o añadir editores, hay que actualizar el UUID del trigger. El UUID está aislado en la migración SQL, no en el cliente.
- **Carrera entre refresh y dismiss**: si el usuario descarta mientras hay un refresh en vuelo que va a reinstalar la ruta, podría reaparecer brevemente. Mitigación: `dismiss` registra el `dismissedAt` en settings antes de borrar del local; el siguiente refresh aplicará la regla normal y la mantendrá descartada (porque el `updated_at` remoto coincide con el guardado).
- **Migración de SQLite**: añadir columnas a una tabla existente con `ALTER TABLE` es seguro en SQLite. La nueva versión del esquema debe incrementar el `version` en `openDatabase` y aplicar la migración condicionalmente.
