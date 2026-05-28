# Sistema de logs (Splitway mobile)

**Fecha:** 2026-05-27
**Rama:** `feat/logging-system`
**Estado:** diseño aprobado, pendiente de plan de implementación

## Problema

Cuando una llamada a Mapbox (geocoding, routing, elevation, thumbnails) o a Supabase (auth, repositorios, sync) falla en producción no queda traza alguna. El código actual hace `catch (_) { return null }` o `debugPrint` aislado, lo que impide diagnosticar incidencias reportadas por usuarios. Se necesita un sistema centralizado de logs persistente, consultable in-app y accesible remotamente.

## Objetivos

- Capturar automáticamente errores y warnings de Supabase, Mapbox/HTTP, auth, tracking y errores no controlados de Flutter/Dart.
- Persistir los logs localmente con retención acotada.
- Subirlos a Supabase en background con cola y reintentos, sin perder eventos si la red o Supabase fallan.
- Permitir al usuario (yo) consultarlos desde una pantalla in-app, filtrarlos y compartirlos.
- No degradar el rendimiento ni filtrar credenciales.

## No-objetivos

- No es analítica de producto ni telemetría de uso.
- No reemplaza crash reporters profesionales (Sentry/Crashlytics).
- No loguea por defecto cada interacción de usuario ni cada request HTTP exitoso.

## Arquitectura

Tres capas independientes que se comunican por el modelo `LogEntry`:

1. **Fachada `AppLogger`** — singleton con API: `log.debug/info/warning/error(tag, message, {error, stack, context})`. Inicializada en `main.dart` antes que Supabase/Mapbox. Aplica sanitización, completa metadatos (versión, plataforma, dispositivo, uid actual) y emite el `LogEntry` a todos los sinks habilitados.
2. **Sinks** — receptores del `LogEntry`:
   - `ConsoleSink` — `debugPrint` formateado, solo en debug builds.
   - `LocalSink` — inserta en tabla SQLite `app_logs` del `SplitwayLocalDatabase` existente.
   - `RemoteSink` — encola en local con `synced=0` y dispara el uploader.
3. **`LogUploader`** — worker que drena filas `synced=0` de SQLite y las inserta en Supabase en lotes de hasta 50 filas. Se activa con debounce (5 s) tras cada log nuevo y al arrancar la app si hay red + sesión Supabase. Marca `synced=1` al éxito; incrementa `sync_attempts` al fallo. Backoff por fila: se reintenta solo cuando han pasado `min(60 * 2^sync_attempts, 3600)` segundos desde su `timestamp`. Tope: `sync_attempts >= 5` → fila descartable por la purga.

**Captura automática:**

- `runZonedGuarded` envuelve `main()` y enruta excepciones async a `log.error('zone', …)`.
- `FlutterError.onError = (details) => log.error('flutter', details.exceptionAsString(), stack: details.stack)`.
- `PlatformDispatcher.instance.onError` redirige a `log.error('dart', …)`.
- Helpers `logSupabase<T>(op, () => …)` y `logHttp(tag, uri, () => …)` envuelven llamadas críticas a Supabase/Mapbox y miden duración.

## Modelo de datos

### `LogEntry` (Dart)

| Campo         | Tipo                       | Notas                                          |
| ------------- | -------------------------- | ---------------------------------------------- |
| `id`          | `String` (uuid v4)         | Generado en cliente, también PK remoto         |
| `timestamp`   | `DateTime` UTC             | Momento del evento                             |
| `level`       | `enum {debug,info,warning,error}` | Persistido como string                  |
| `tag`         | `String`                   | `supabase`, `mapbox`, `auth`, `sync`, `flutter`, `dart`, `http`, `location`, `app` |
| `message`     | `String`                   | Texto humano corto                             |
| `error`       | `String?`                  | `toString()` de la excepción (sanitizado)      |
| `stackTrace`  | `String?`                  | `StackTrace.toString()` (sanitizado)           |
| `context`     | `Map<String,dynamic>?`     | `{url, statusCode, method, durationMs, …}` (sanitizado, serializado a JSON) |
| `appVersion`  | `String`                   | De `package_info_plus`                         |
| `platform`    | `String`                   | `android 14` / `ios 17.4` / …                  |
| `deviceModel` | `String`                   | `Pixel 7` / `iPhone 13` / …                    |
| `userId`      | `String?`                  | `Supabase.instance.client.auth.currentUser?.id`|

### Tabla SQLite `app_logs`

Mismas columnas + `synced INTEGER NOT NULL DEFAULT 0` y `sync_attempts INTEGER NOT NULL DEFAULT 0`. Índices: `(synced, timestamp)` para el uploader, `(timestamp DESC)` para la pantalla, `(level, tag)` para filtros.

Migración: añadida como nueva versión de `SplitwayLocalDatabase` (bump de versión + `onUpgrade` con `CREATE TABLE`).

### Tabla Supabase `public.app_logs`

Mismas columnas que `LogEntry` (sin `synced`/`sync_attempts`). PK = `id` (uuid). `user_id` nullable referencia `auth.users(id) ON DELETE SET NULL`.

**RLS:**

- `INSERT`: permitido a `authenticated` cuando `user_id = auth.uid()` o `user_id IS NULL` (para errores pre-login).
- `SELECT`/`DELETE`/`UPDATE`: solo `service_role` (consulta vía dashboard, no desde la app).

**Retención remota:** `pg_cron` daily job que ejecuta `DELETE FROM app_logs WHERE timestamp < now() - interval '30 days';`

**Migración SQL:** `supabase/migrations/<timestamp>_app_logs.sql` con tabla + índices + políticas RLS + cron job.

## Sanitización

Antes de persistir cualquier `LogEntry`, `LogSanitizer` aplica:

- Sobre URLs y strings de error/stack: regex que reemplaza `access_token=...`, `apikey=...`, `Bearer ...` por `***REDACTED***`.
- Sobre `context`: si alguna clave coincide con la blacklist `{password, token, apikey, authorization, refresh_token, access_token}`, su valor se reemplaza por `***REDACTED***`.
- Nunca se loguean email/password en `auth_service.dart`.

## Puntos de captura concretos

**Globales (`main.dart`):**
- `AppLogger.init(...)` ANTES de `Supabase.initialize` y `MapboxOptions.setAccessToken` para capturar fallos de arranque.
- `runZonedGuarded` envolviendo todo `main`.
- `FlutterError.onError` y `PlatformDispatcher.instance.onError`.

**Supabase** — envoltorio `logSupabase` aplicado en:
- `supabase_repository.dart`: `upsertRoute`, `fetchAllRoutes`, `deleteRoute`, `upsertSession`, `fetchAllSessions`, `fetchSession`, `deleteSession`, `upsertFreeRide`, `fetchAllFreeRides`, `fetchFreeRide`, las 3 funciones `fetch*Timestamps`.
- `auth_service.dart`: login email/password, signup, google sign-in, logout.
- `profile_repository.dart`, `garage_repository.dart`, `speed_repository.dart`: métodos públicos que tocan Supabase.
- `sync_service.dart`: cada paso del ciclo de sync.

**Mapbox / HTTP** — envoltorio `logHttp` (solo loguea si status ≥ 400 o lanza) aplicado en:
- `reverse_geocoding_service.dart`, `forward_geocoding_service.dart`, `routing_service.dart`, `elevation_service.dart`, `route_thumbnail_service.dart`.
- Los `catch (_) { return null }` actuales se reemplazan por `catch (e, st) { log.warning('mapbox', '...', error: e, stack: st); return null; }` — degradación con gracia preservada, pero queda traza.

**Auth y tracking:**
- `auth_service.dart`: fallos con `tag: 'auth'` + código de error (sin credenciales).
- `location_service.dart`: denegación de permisos GPS y errores del stream con `tag: 'location'`.

## Pantalla in-app

Nueva ruta `/settings/logs` accesible desde un nuevo item "Diagnóstico" en `settings_screen.dart`.

**Layout:**
- AppBar con título y botón "borrar todo" (con confirmación).
- Header: chip `X pendientes de subir` + botones "Subir ahora" y "Compartir todo".
- Barra de filtros (chips): nivel (debug/info/warning/error), tag (supabase/mapbox/…), búsqueda por texto sobre `message`.
- Lista virtualizada (`ListView.builder`): cada tile muestra icono según nivel, timestamp relativo (`Formatters` existente), tag y mensaje truncado a 2 líneas. Borde izquierdo coloreado por nivel.
- Tap abre `log_detail_sheet.dart` (modal bottom sheet): mensaje, error, stack, context JSON pretty-printed, metadatos. Botones "Copiar" y "Compartir este log".

**Compartir:** usa `share_plus` (ya en `pubspec.yaml`) — exporta a `.txt` con header de metadatos del dispositivo y los logs filtrados, abre el sheet nativo.

**Localización:** strings añadidos a `app_localizations_en.dart` y `app_localizations_es.dart` (claves `logsScreen*`).

## Retención local

Tras cada N=100 inserts en `LocalSink`:
- `DELETE FROM app_logs WHERE timestamp < datetime('now', '-7 days')`.
- Si `count(*) > 2000`, borra las más antiguas hasta dejar 2000.

Las filas con `synced=0` no se borran aunque venzan, para no perder logs no subidos (se sube primero, se borra luego). Excepción: si `sync_attempts >= 5`, se considera "muertas" y son elegibles para purga.

## Configuración

`AppSettingsController` añade:
- `minLogLevel` (default `warning`). Cambiable desde la pantalla "Diagnóstico" para subir verbosidad temporalmente.
- `remoteLogsEnabled` (default `true`). Apagable si el usuario quiere mantener los logs solo locales.

## Testing

- Unit tests:
  - `AppLogger`: respeta `minLogLevel`, completa metadatos, despacha a sinks habilitados.
  - `LogSanitizer`: redacta tokens en URL/headers/context; conserva el resto.
  - `LocalSink`: insert, filtros, retención por días y por count, no borra `synced=0`.
  - `RemoteSink` + `LogUploader`: marca `synced=1` al éxito; incrementa intentos al fallo; backoff; respeta tope de 5 intentos.
  - `logSupabase` / `logHttp`: loguean en error, no loguean en éxito (excepto duración en debug).
- Widget test mínimo de `logs_screen.dart`: renderiza lista, los filtros recortan resultados, abrir detalle muestra contenido.

## Estructura de archivos nuevos

```
movile_app/lib/src/services/logging/
  app_logger.dart
  log_entry.dart
  log_level.dart
  log_sanitizer.dart
  log_uploader.dart
  http_logging.dart           // helpers logSupabase, logHttp
  sinks/
    log_sink.dart             // interfaz
    console_sink.dart
    local_sink.dart
    remote_sink.dart

movile_app/lib/src/features/logs/
  logs_screen.dart
  log_detail_sheet.dart
  widgets/log_list_tile.dart
  widgets/log_filter_bar.dart

supabase/migrations/
  20260527_app_logs.sql

movile_app/test/services/logging/
  app_logger_test.dart
  log_sanitizer_test.dart
  local_sink_test.dart
  remote_sink_test.dart
  http_logging_test.dart

movile_app/test/features/logs/
  logs_screen_test.dart
```

## Dependencias nuevas

- `package_info_plus: ^8.0.0` (versión app).
- `device_info_plus: ^11.0.0` (modelo dispositivo + versión OS).

Ambas son first-party de flutter.dev y de uso muy común.

## Riesgos

- **Log storms:** un bucle de errores puede saturar la tabla. Mitigación: rate-limit en `AppLogger` (max 10 logs/segundo por tag; el resto se cuenta como "N logs deduplicados").
- **PII en stack traces:** rutas de archivos del dispositivo pueden aparecer. Aceptado, no se considera PII sensible.
- **Coste de Supabase:** 30 días × N usuarios × eventos puede crecer. Mitigación: `pg_cron` agresivo + posibilidad de apagar remoto por usuario.
- **Migración SQLite:** bump de versión de DB local. Asegurar que `onUpgrade` solo crea la tabla nueva, sin tocar las existentes.
