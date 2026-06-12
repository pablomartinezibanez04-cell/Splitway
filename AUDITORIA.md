# Auditoría técnica de Splitway

> Fecha: 2026-06-10 · Rama auditada: `feat/admin-logs` · Auditor: revisión automatizada (Claude Code)
>
> **Actualización 2026-06-11:** todos los bugs de correctitud (BUG-1…BUG-13) y los hallazgos de seguridad accionables por código (SEC-1…SEC-5) han sido corregidos. Ver [§10. Correcciones de bugs](#10-correcciones-aplicadas-2026-06-11) y [§11. Correcciones de seguridad y dedup](#11-correcciones-de-seguridad-y-dedup-2026-06-11-segunda-tanda). Pendiente de operación: SEC-11/SEC-12; pendiente con tests: DUP-1.

## 1. Resumen ejecutivo

Splitway es un monorepo con cuatro componentes principales:

| Componente | Tecnología | Rol |
|---|---|---|
| `movile_app/` | Flutter (Dart, SDK ^3.5) | App móvil (cronómetro de rutas, GPS, sync offline) |
| `admin/` | Next.js 16 + React 19 + Supabase SSR | Panel de administración |
| `packages/splitway_core/` | Dart | Modelos de dominio compartidos |
| `supabase/` | Postgres 17 + Edge Functions (Deno) | Backend, RLS, migraciones |

**Veredicto general: es un código maduro y bien diseñado en seguridad.** Los fundamentos son sólidos: Row-Level Security activada en todas las tablas, funciones `SECURITY DEFINER` con `search_path` fijado y permisos revocados correctamente, defensa en profundidad en el panel admin (middleware + guard en cada server action), saneamiento de logs y gestión correcta de secretos (ninguno está en el repositorio ni en el historial de git). No se encontraron vulnerabilidades críticas ni de severidad alta.

Los problemas detectados son de severidad **media o baja** y se concentran en tres áreas: (1) un par de endpoints sin control de abuso/coste, (2) bugs de correctitud en la capa de sincronización, y (3) duplicación de código repetitivo en el panel admin.

### Puntuación

| Dimensión | Nota /10 | Comentario |
|---|---:|---|
| Seguridad (authn/authz, RLS, secretos) | 8.0 | Muy buena base; faltan límites de abuso y un par de comprobaciones de rol |
| Correctitud (lógica, sync) | 6.5 | Bug real de pérdida de cambios en sync entre dispositivos |
| Calidad de código / mantenibilidad | 7.5 | Limpio y comentado, pero con duplicación evitable |
| Robustez / manejo de errores | 8.0 | Defensivo, sinks que no lanzan, reintentos con tope |
| Tooling / CI / pruebas | 6.5 | Hay tests, falta CI con lin[t]/secret-scan/audit de deps visible |
| **Global** | **7.5** | Proyecto sólido, listo para producción tras cerrar los hallazgos medios |

### Cobertura de la auditoría

Revisado en profundidad: todas las migraciones SQL y políticas RLS, las 2 Edge Functions, toda la capa de autenticación/autorización del admin (`lib/auth.ts`, `proxy.ts`, server.ts, admin.ts) y sus server actions, el subsistema de logging del móvil (logger, sanitizer, sinks, uploader), `SyncService`, `AuthService`, `AppConfig` y la gestión de secretos. **No** revisado a fondo: UI completa de Flutter, `background_tracking_service`, `speed_measurement_service`, internals de `splitway_core`, y la totalidad de componentes React del admin. Son candidatos a una segunda pasada.

---

## 2. Vectores de ataque y hallazgos de seguridad

### 🟠 SEC-1 (Media) — `mapbox-routing` no valida el JWT y carece de control de abuso

**Archivo:** [supabase/functions/mapbox-routing/index.ts:39-45](supabase/functions/mapbox-routing/index.ts)

La función comenta *"Verify the caller is authenticated via Supabase JWT"* pero solo comprueba la **presencia** de la cabecera `Authorization`, nunca valida el token (a diferencia de `delete-user`, que sí llama a `auth.getUser()`). Como la gateway de Supabase verifica el JWT por defecto, en la práctica la función queda accesible para cualquier portador de un JWT válido — incluida la **anon key**, que va embebida en el bundle de la app móvil y es por tanto pública/extraíble. No hay rate-limiting ni cuota por usuario.

**Impacto:** abuso del token *secreto* de Mapbox (Map Matching API), que sí cuesta dinero → vector de coste/DoS económico. Cualquiera que extraiga la anon key puede invocar el proxy en bucle.

**Solución:**
- Validar realmente el JWT dentro de la función (replicar el patrón de `delete-user`: `anonClient.auth.getUser(token)` y rechazar si falla).
- Añadir rate-limiting por `user.id` (token-bucket en una tabla Postgres, o cuota diaria).
- Restringir `Access-Control-Allow-Origin` a orígenes conocidos en lugar de `*`.
- Validar/limitar `profile`, `radiuses` y `timestamps` (hoy `profile` se interpola en la URL sin lista blanca estricta del lado del valor recibido).

### 🟠 SEC-2 (Media) — `app_logs`: inserción de logs arbitrarios sin límite (flooding / inyección de diagnósticos)

**Archivo:** [supabase/migrations/20260527000000_app_logs.sql:24-28](supabase/migrations/20260527000000_app_logs.sql)

La política de insert `with check (user_id = auth.uid() or user_id is null)` permite a **cualquier usuario autenticado** insertar filas con `message`, `error`, `stack_trace`, `context` (jsonb), `app_version`, `platform`, `device_model` **arbitrarios**, sin límite de tamaño ni rate-limit en servidor. El rate-limit de 10/seg existe solo en el cliente ([app_logger.dart:151](movile_app/lib/src/services/logging/app_logger.dart)) y un cliente modificado lo ignora.

**Impacto:** inflado de almacenamiento/coste, contaminación de los diagnósticos con datos falsos (versiones, plataformas, errores inventados). El riesgo de **XSS almacenado** en el panel está mitigado porque React escapa por defecto y el detalle usa JSX/`JSON.stringify`, sin `dangerouslySetInnerHTML` ([log-detail-sheet.tsx](admin/app/(dashboard)/logs/log-detail-sheet.tsx)) — pero la pollution/flooding sí es real.

**Solución:**
- `CHECK` de longitud máxima en `message`, `error`, `stack_trace`, `tag`, `app_version`, etc., y tope de tamaño del jsonb `context`.
- Throttle por usuario vía trigger (p.ej. máx N inserts/minuto por `user_id`), o mover la ingesta detrás de una Edge Function que valide y limite.
- La purga diaria a 30 días vía `pg_cron` ya está bien planteada.

### 🟡 SEC-3 (Baja-Media) — Un `admin` puede banear / resetear / editar a un `superadmin`

**Archivo:** [admin/app/(dashboard)/users/[id]/actions.ts:79-118](admin/app/(dashboard)/users/[id]/actions.ts)

`banUser` solo bloquea el auto-baneo (`userId === admin.id`). Un usuario con rol `admin` (no superadmin) puede banear, resetear la contraseña o editar el perfil de un `superadmin`, lo que permite que un admin deshonesto **bloquee a los superadmins** del sistema. Contrasta con `demoteAdmin`/`promoteAdmin`, que sí exigen `requireSuperadmin()` y protegen a los superadmins.

**Solución:** antes de mutar, leer el rol del objetivo y rechazar la acción si es `superadmin` (salvo que el llamante también lo sea). Idealmente, las acciones destructivas sobre cualquier `admin` deberían exigir `requireSuperadmin()`.

### 🟡 SEC-4 (Baja) — Posible open-redirect post-login vía `x-forwarded-host`

**Archivo:** [admin/app/auth/callback/route.ts:21-25](admin/app/auth/callback/route.ts)

El callback OAuth construye el `origin` del redirect a partir de `x-forwarded-host` / `x-forwarded-proto` sin lista blanca. Si el despliegue no sanea esas cabeceras (un proxy mal configurado), un atacante podría provocar que el redirect final apunte a un host arbitrario. El `code` es de un solo uso y ya se ha canjeado, y las cookies se fijan sobre el dominio legítimo, por lo que el robo de sesión no es directo; el riesgo es redirección no deseada / phishing.

**Solución:** validar `host` contra una lista blanca (o usar una `NEXT_PUBLIC_SITE_URL` configurada) en lugar de confiar en cabeceras del cliente.

### 🟡 SEC-5 (Baja) — `resetUserPassword` no verifica que el email corresponda al `userId`

**Archivo:** [admin/app/(dashboard)/users/[id]/actions.ts:162-198](admin/app/(dashboard)/users/[id]/actions.ts)

El email se toma del formulario de forma independiente del `userId`, y es ese email el que se pasa a `generateLink`. Solo lo invocan admins (impacto bajo), pero el log de auditoría registra `targetId = userId` mientras que el correo podría ser otro → desajuste de auditoría.

**Solución:** derivar el email del `userId` en servidor (vía `find_email_by_user_id` o `auth.admin`) en vez de aceptarlo del cliente.

### ℹ️ Hallazgos informativos / aceptados

- **SEC-6 — CORS `*`** en ambas Edge Functions: aceptable al no usar cookies, pero conviene restringir.
- **SEC-7 — `get_user_ban_until`** expone "email X baneado hasta Y" a quien adivine el email. Documentado y asumido como trade-off ([migración](supabase/migrations/20260528000010_get_user_ban_until.sql)).
- **SEC-8 — Identidades hardcodeadas**: superadmin `pabmariba@gmail.com` ([seed](supabase/migrations/20260528000001_seed_superadmin.sql)) y curador `splitwayoficial@gmail.com` ([trigger](supabase/migrations/20260606000000_official_routes_public_read.sql)). Frágil operativamente; mejor por configuración/env.
- **SEC-9 — Token Mapbox público en el bundle**: `MAPBOX_ACCESS_TOKEN` se embebe vía `env/local.json` (asset) o `--dart-define` y se usa para render, static images y geocoding ([app_config.dart:49](movile_app/lib/src/config/app_config.dart)). Es el modelo esperado de Mapbox (token `pk.` público), pero **debe** llevar restricciones de URL/scoping en el dashboard de Mapbox. El token *secreto* queda correctamente aislado en la Edge Function.
- **SEC-10 — Gestión de secretos correcta**: `.env`, `client_secret*.json`, `env/local.json` están en `.gitignore` y **no aparecen en el historial de git**. Único detalle de limpieza: `.claude/settings.local.json` está trackeado pese al patrón `.claude/*` (no contiene secretos; conviene `git rm --cached`).

---

## 3. Bugs y problemas de correctitud

### 🟠 BUG-1 (Media) — Las ediciones de rutas ya sincronizadas no se vuelven a subir

**Archivo:** [movile_app/lib/src/services/sync/sync_service.dart:165-167](movile_app/lib/src/services/sync/sync_service.dart)

La estrategia documentada es *last-write-wins por `updated_at`*, pero la decisión de push de rutas compara `route.createdAt.isAfter(remoteUpdated)`:

```dart
final needsPush = remoteUpdated == null ||
    route.createdAt.isAfter(remoteUpdated);  // ⚠️ debería ser updatedAt
```

Como `createdAt` no cambia al editar, una ruta ya subida que se edita localmente **nunca se vuelve a empujar** → pérdida silenciosa de cambios entre dispositivos.

**Solución:** comparar contra el `updatedAt` de la ruta (y asegurarse de que `RouteTemplate` lo expone y se actualiza en cada edición local).

### 🟡 BUG-2 (Baja-Media) — El pull no actualiza filas locales existentes (sesiones / free rides)

**Archivo:** [sync_service.dart:229-241 y 261-272](movile_app/lib/src/services/sync/sync_service.dart)

El pull solo trae elementos cuyo `id` **no** existe localmente (`!localSessionIds.contains(remoteId)`). Si una sesión/ride se edita en otro dispositivo, el dispositivo que ya la tiene nunca recibe la versión nueva. Inconsistente con la estrategia LWW (que el bloque de rutas sí intenta, aunque con el bug BUG-1).

**Solución:** comparar timestamps remoto vs local también en el pull y sobrescribir cuando el remoto sea más reciente.

### 🟡 BUG-3 (Baja-Media) — La reconciliación puede borrar rutas locales ante un fetch remoto vacío

**Archivo:** [sync_service.dart:189-195](movile_app/lib/src/services/sync/sync_service.dart)

Se borran las rutas locales no oficiales que no estén en `remoteRouteTs` y no se hayan empujado. Si `fetchRouteTimestamps()` devolviera un conjunto vacío o parcial **sin lanzar excepción** (degradación transitoria, paginación), se borrarían rutas locales válidas.

**Solución:** salvaguarda — omitir la fase de reconciliación si el fetch remoto resulta sospechosamente vacío, o usar tombstones explícitos de borrado en vez de inferir el borrado por ausencia.

### 🟡 BUG-4 (Baja) — `upsert_session_with_telemetry` hace no-op silencioso ante colisión de `id` de otro dueño

**Archivo:** [supabase/migrations/20260519090000_add_free_rides_and_atomic_sync.sql:121-153](supabase/migrations/20260519090000_add_free_rides_and_atomic_sync.sql)

El `ON CONFLICT (id) DO UPDATE ... WHERE session_runs.owner_id = v_uid` no actualiza si la fila pertenece a otro usuario, pero **no lanza error**; luego se insertan `telemetry_points` con `session_id = p_id` (de otro dueño) y `owner_id = v_uid`. RLS evita la fuga de lectura, pero queda telemetría huérfana referenciando una sesión ajena. (Los `id` son generados por cliente, así que es explotable a propósito conociendo un id ajeno.)

**Solución:** detectar la colisión de propiedad y `RAISE EXCEPTION` (o saltar también el insert de telemetría).

### 🟡 BUG-5 (Baja) — Funciones de upsert sin `search_path` fijado

**Archivo:** [misma migración, funciones `upsert_session_with_telemetry` y `upsert_free_ride_with_telemetry`](supabase/migrations/20260519090000_add_free_rides_and_atomic_sync.sql)

A diferencia del resto de funciones del proyecto, estas dos no hacen `set search_path = public`. Son `SECURITY INVOKER` (riesgo menor), pero conviene la consistencia y el endurecimiento.

### 🟡 BUG-6 (Baja) — `delete-user`: lista la misma carpeta dos veces y solo purga un nivel de anidamiento

**Archivo:** [supabase/functions/delete-user/index.ts:22-53](supabase/functions/delete-user/index.ts)

`purgeUserStorage` ejecuta `.list(userId)` dos veces seguidas (la primera lista es prácticamente redundante) y solo desciende **un** nivel de subcarpetas. Estructuras más profundas dejan objetos huérfanos en storage tras eliminar la cuenta.

**Solución:** una sola listada + recursión genérica sobre subcarpetas (items con `metadata === null`).

### 🟡 BUG-7 (Baja) — `LogSanitizer.sanitizeContext` no recorre estructuras anidadas

**Archivo:** [movile_app/lib/src/services/logging/log_sanitizer.dart:38-55](movile_app/lib/src/services/logging/log_sanitizer.dart)

Solo sanea valores `String` de primer nivel. Si `context` contiene un `Map`/`List` anidado con un token (p.ej. `{'response': {'access_token': '...'}}`), no se redacta. Además la blacklist no incluye `email`, `cookie`, `set-cookie`, `secret`, `jwt`, `session`.

**Solución:** recursión sobre maps/listas y ampliar la lista de claves sensibles.

### ℹ️ Menores

- **BUG-8** — `admin_audit_log` declaraba `admin_id NOT NULL` con FK `ON DELETE SET NULL` (contradictorio); ya **corregido** en [migración follow-up 20260528000004](supabase/migrations/20260528000004_fix_admin_audit_log_nullable_admin_id.sql). Documentado.
- **BUG-9** — Código muerto en [auth_service.dart:136](movile_app/lib/src/services/auth/auth_service.dart): `const String? accessToken = null;` que solo se pasa como `null`.

---

## 4. Condiciones de carrera

La buena noticia: el modelo de un solo isolate de Dart protege la mayoría de los guards. Conviene documentar la invariante y vigilar dos puntos:

- **`SyncService.sync()`** ([sync_service.dart:108-118](movile_app/lib/src/services/sync/sync_service.dart)): el guard `if (_status == SyncStatus.syncing) return;` seguido de `_status = SyncStatus.syncing` es **seguro** porque check y set ocurren de forma síncrona antes de cualquier `await`. Disparadores concurrentes (timer periódico + cambio de conectividad + manual) se deduplican correctamente. ✅
- **`LogUploader.drain()`** ([log_uploader.dart:44-47](movile_app/lib/src/services/logging/log_uploader.dart)): mismo patrón síncrono con `_running`. ✅ Matiz: una llamada concurrente retorna de inmediato sin esperar al drain en curso; si el llamante asume que "ya se subió", podría equivocarse. Impacto bajo.
- **Pendiente de revisar**: `background_tracking_service`, `live_tracking_controller` y `speed_measurement_service` no se auditaron a fondo. Como manejan timers, sensores y posiblemente foreground tasks, son los candidatos más probables a carreras reales (estado compartido entre callbacks de sensores/GPS y la UI). Recomiendo una pasada dirigida.

No se detectaron carreras en SQL: los upserts atómicos vía RPC sustituyen correctamente el antiguo patrón delete+insert no atómico (ese era el objetivo de la [migración de sync atómico](supabase/migrations/20260519090000_add_free_rides_and_atomic_sync.sql)).

---

## 5. Código duplicado

| ID | Patrón duplicado | Dónde | Propuesta |
|---|---|---|---|
| DUP-1 | Boilerplate de server action (`requireAdmin` → `zod.safeParse` → `adminClient()` → mutación → `writeAuditLog` → `revalidatePath`) | 10× `actions.ts` en `admin/app/(dashboard)/**` | Extraer un helper `defineAdminAction({ schema, role, audit, run })` que centralice guard + parse + auditoría |
| DUP-2 | `delete-dialog.tsx` casi idénticos | rutas, runs, free-rides, speed-sessions (4×) | Un único `<DeleteEntityDialog>` genérico parametrizado por acción/etiqueta |
| DUP-3 | `filters-bar.tsx` (4×) y `pagination.tsx` (3×) | logs, routes, sessions, users | Componentes compartidos parametrizados por config de columnas/filtros |
| DUP-4 | `upsert_session_with_telemetry` y `upsert_free_ride_with_telemetry` casi idénticos | migración de sync atómico | Helper SQL común para el bloque de inserción de telemetría |
| DUP-5 | Cabeceras CORS repetidas | ambas Edge Functions | `supabase/functions/_shared/cors.ts` |

Ninguna de estas duplicaciones es un bug, pero amplifican el coste de mantenimiento y el riesgo de que un fix se aplique en un sitio y no en los otros (p.ej. si DUP-1 olvidara el guard en una acción nueva → escalada de privilegios). DUP-1 es la de mayor valor por seguridad: un wrapper único garantiza que ninguna acción quede sin `requireAdmin`.

---

## 6. Mejoras de implementación e ideas nuevas

### Seguridad y backend
- **Rate-limiting / cuotas** para Edge Functions e ingesta de logs (token-bucket en Postgres o gateway). Cierra SEC-1 y SEC-2.
- **Suite de tests de RLS con pgTAP**: aserciones de aislamiento por usuario para que ningún cambio futuro de política rompa la separación de datos sin que el CI lo detecte.
- **`CHECK` de longitud** en columnas escribibles por el usuario (`app_logs.*`, `profiles.bio/nickname`) — hoy el límite vive solo en Zod (cliente/admin), no en la BD.
- **Pinear versiones** de dependencias Deno en Edge Functions: `mapbox-routing` usa `deno.land/std@0.168.0` (antiguo) y `delete-user` usa `esm.sh/@supabase/supabase-js@2` (minor flotante). Fijar versiones reproducibles.
- **Migración de sync a modelo change-log + tombstones**: resuelve BUG-1/2/3 de raíz con `updated_at` autoritativo del servidor y borrados explícitos en lugar de inferencia por ausencia.

### Tooling / CI
- Pipeline CI que ejecute: `flutter analyze` + `dart test`, `tsc --noEmit` + `eslint` (admin), `supabase db lint`, **secret-scanning** (gitleaks/trufflehog) y **audit de dependencias** (`pnpm audit`, `flutter pub outdated`).
- **Test/lint que verifique que toda server action llama a un guard** (atado a DUP-1): regla custom o test de integración.

### Producto / arquitectura
- Identidades de superadmin/curador **por configuración** (env/secret), no hardcodeadas en migraciones.
- **Observabilidad**: integrar Sentry/Crashlytics como complemento del logger propio para capturar crashes nativos no cubiertos por el pipeline Dart actual.
- **Token Mapbox**: documentar y aplicar restricciones de URL/scoping en el dashboard, y considerar enrutar también geocoding/static-images por una Edge Function si el volumen lo justifica (mismo patrón que `mapbox-routing`).
- **Tope de tamaño por fila de telemetría** y compresión, dado que `upsert_*_with_telemetry` recibe arrays jsonb potencialmente grandes.

---

## 7. Lo que está especialmente bien hecho

Para equilibrar el informe, conviene destacar lo correcto, porque marca el nivel del proyecto:

- **RLS exhaustiva** en todas las tablas de usuario, con políticas aditivas bien razonadas para el catálogo público de rutas oficiales ([migración 20260606](supabase/migrations/20260606000000_official_routes_public_read.sql)).
- **Higiene de `SECURITY DEFINER`**: `search_path` fijado y `REVOKE ... FROM public/anon/authenticated` + `GRANT ... TO service_role` en las funciones sensibles (`find_user_id_by_email`, `duplicate_route_as_official`).
- **Trigger `enforce_official_owner`**: impide publicar rutas `is_official` salvo desde la cuenta curadora, incluso si alguien llamara directamente a PostgREST.
- **Defensa en profundidad en el admin**: gate en `proxy.ts` (middleware) + `requireAdmin`/`requireSuperadmin` en cada server action, todo validado con Zod y auditado.
- **`service_role` correctamente aislado** tras `import "server-only"` ([admin.ts](admin/lib/supabase/admin.ts)); nunca llega al cliente.
- **Logging defensivo**: sanitización antes de persistir, sinks que no lanzan, reintentos con tope (`sync_attempts < 5`), retención y purga local + remota.
- **Secretos fuera del control de versiones**, confirmado también en el historial.

---

## 8. Tabla resumen de hallazgos

| ID | Sev. | Título | Archivo |
|---|---|---|---|
| SEC-1 | 🟠 Media | `mapbox-routing` no valida JWT, sin rate-limit | `supabase/functions/mapbox-routing/index.ts` |
| SEC-2 | 🟠 Media | `app_logs` permite inserción arbitraria sin límite | `supabase/migrations/20260527000000_app_logs.sql` |
| SEC-3 | 🟡 Baja-Media | Admin puede banear/editar a superadmin | `admin/app/(dashboard)/users/[id]/actions.ts` |
| SEC-4 | 🟡 Baja | Open-redirect post-login vía `x-forwarded-host` | `admin/app/auth/callback/route.ts` |
| SEC-5 | 🟡 Baja | `resetUserPassword` no liga email↔userId | `admin/app/(dashboard)/users/[id]/actions.ts` |
| BUG-1 | 🟠 Media | Ediciones de ruta no se re-suben (usa `createdAt`) | `movile_app/lib/src/services/sync/sync_service.dart` |
| BUG-2 | 🟡 Baja-Media | Pull no actualiza filas locales existentes | `sync_service.dart` |
| BUG-3 | 🟡 Baja-Media | Reconciliación borra ante fetch remoto vacío | `sync_service.dart` |
| BUG-4 | 🟡 Baja | Upsert no-op silencioso ante id ajeno | `20260519090000_add_free_rides_and_atomic_sync.sql` |
| BUG-5 | 🟡 Baja | Upserts sin `search_path` | misma migración |
| BUG-6 | 🟡 Baja | `delete-user` purga storage incompleta | `supabase/functions/delete-user/index.ts` |
| BUG-7 | 🟡 Baja | `sanitizeContext` no recorre anidados | `movile_app/lib/src/services/logging/log_sanitizer.dart` |
| DUP-1 | ⚪ Calidad | Boilerplate de server actions ×10 | `admin/app/(dashboard)/**/actions.ts` |
| DUP-2..5 | ⚪ Calidad | Componentes/funciones casi idénticas | varios |

**Prioridad recomendada:** SEC-1 → BUG-1 → SEC-2 → SEC-3 → resto.

---

## 9. Segunda pasada — hallazgos complementarios

> Esta pasada cubre las zonas que la primera dejó pendientes: tracking en background, sensores/velocidad, base de datos local SQLite, repositorios, `splitway_core`, las vistas del admin y el resto de migraciones (perfiles, vehículos, speed sessions, cuenta curadora). Confirma que los fundamentos siguen siendo sólidos y añade los siguientes hallazgos nuevos.

### Seguridad

#### 🟠 SEC-11 (Media, condicional) — Cuenta superadmin curadora vía inserciones crudas en `auth.users` + posible toma de control por email

**Archivos:** [supabase/migrations/20260601000005_splitway_owns_official_routes.sql](supabase/migrations/20260601000005_splitway_owns_official_routes.sql), [20260601000006_rename_splitway_email.sql](supabase/migrations/20260601000006_rename_splitway_email.sql)

La cuenta de sistema curadora (dueña de todas las rutas oficiales y con rol `superadmin`) acabó siendo `splitwayoficial@gmail.com`. En su creación se insertan filas directamente en `auth.users` y `auth.identities` (con `instance_id`, `aud`, `encrypted_password`, `raw_app_meta_data`, etc. a mano). Dos problemas:

1. **Fragilidad**: manipular el esquema interno de GoTrue (Supabase Auth) por SQL crudo se rompe si Supabase cambia columnas/invariantes; es un anti-patrón frente a usar la Admin API (`auth.admin.createUser`).
2. **Riesgo de toma de control (condicional)**: es una cuenta `superadmin` con `email_confirmed_at` y sin contraseña. Si el buzón `splitwayoficial@gmail.com` **no está realmente registrado y controlado por el equipo**, un atacante podría registrar ese Gmail, lanzar "recuperar contraseña" en el panel admin y fijar una contraseña → control total de un superadmin.

**Solución:**
- **Verificar que el equipo posee y controla ese buzón Gmail** (acción operativa, no de código). Si no, este es un hallazgo de severidad alta.
- Preferir la Admin API para crear/gestionar la cuenta de sistema en vez de inserciones crudas.
- Considerar deshabilitar la recuperación de contraseña / sign-in interactivo para cuentas de sistema, o convertirla en una cuenta sin email canjeable.

#### 🟡 SEC-12 (Baja) — Datos sensibles locales sin cifrar en reposo

**Archivo:** [movile_app/lib/src/data/local/splitway_local_database.dart](movile_app/lib/src/data/local/splitway_local_database.dart)

La base SQLite (`splitway.db`) guarda telemetría GPS, sesiones, perfil y la tabla local `app_logs` (con `user_id`) sin cifrar. En el sandbox de la app es razonable, pero en dispositivos rooteados/jailbroken es legible. Es un trazado completo de la ubicación del usuario.

**Solución:** valorar SQLCipher (o `sqflite_sqlcipher`) para los datos sensibles, o al menos documentar el modelo de amenaza y minimizar la retención local de telemetría.

#### ℹ️ SEC-13 (Informativo, ya mitigado) — `vehicle-photos` permitía SVG (XSS) en su creación

**Archivos:** [20260520000001_add_vehicles.sql:47](supabase/migrations/20260520000001_add_vehicles.sql) (creación con `allowed_mime_types = ARRAY['image/*']`) → corregido en [20260520000003_harden_storage_buckets.sql](supabase/migrations/20260520000003_harden_storage_buckets.sql) (restringido a jpeg/png/webp). El bucket además es privado y con políticas por carpeta de usuario. **Mitigado**; se documenta la dependencia del orden de migraciones (un proyecto que solo aplicara la primera quedaría expuesto a SVG con `<script>`).

#### ✅ Confirmaciones positivas de esta pasada

- **Vistas del admin** (`admin_users_view`, `admin_routes_view`, `admin_app_logs_view`, sesiones): aunque por diseño de Postgres corren con privilegios del dueño (no llevan `security_invoker`), tienen `revoke all ... from public, anon, authenticated` y solo `grant select ... to service_role`. El propio código documenta el riesgo y "repite" los grants como defensa. ✅
- **RLS de `profiles`, `vehicles`, `speed_sessions`**: estrictamente por dueño (`auth.uid() = id/user_id`) en todas las operaciones. Las políticas de Storage scopean por carpeta `{user_id}/`. ✅
- **`enforce_official_owner`** y las RPC `toggle_route_official` / `duplicate_route_as_official` / `get_splitway_user_id`: `SECURITY DEFINER`, `search_path` fijado, ejecutables solo por `service_role`. Un cliente que intente `is_official = true` es rechazado por el trigger. ✅
- **Sin inyección SQL**: la BD local usa la API estructurada de `sqflite` con placeholders; `_ownerFilter` es una cadena constante con `?` y `_ownerArgs` aporta los valores. El geocoding usa `Uri.encodeComponent` sobre la query del usuario. ✅
- **`signOut`** ([(dashboard)/actions.ts](admin/app/(dashboard)/actions.ts)) sin guard pero inofensivo (solo cierra la sesión del propio llamante). ✅

### Bugs y correctitud

#### 🟠 BUG-10 (Media) — Reemplazo de sectores no atómico en `upsertRoute` (riesgo de pérdida de sectores)

**Archivo:** [movile_app/lib/src/data/repositories/supabase_repository.dart:67-73](movile_app/lib/src/data/repositories/supabase_repository.dart)

Al subir una ruta, los sectores se reemplazan con un patrón `DELETE ... WHERE route_id` seguido de un `INSERT`, en **dos llamadas HTTP separadas a PostgREST, sin transacción**:

```dart
await logSupabase('upsertRoute.deleteSectors',
    () => _client.from('sectors').delete().eq('route_id', route.id));
if (route.sectors.isNotEmpty) {
  await logSupabase('upsertRoute.insertSectors', () => _client.from('sectors').insert(...));
}
```

Si el `insert` falla (red, validación) **después** de que el `delete` haya tenido éxito, la ruta remota queda **sin ningún sector**. Es exactamente el patrón no atómico que las RPC `upsert_session_with_telemetry` / `upsert_free_ride_with_telemetry` se crearon para evitar — pero los sectores de rutas se quedaron fuera de ese refactor.

**Solución:** crear una RPC `upsert_route_with_sectors` (mismo modelo que las de sesiones) que haga delete+insert dentro de una sola transacción server-side.

#### 🟠 BUG-11 (Media) — `SpeedMeasurementService` filtra suscripciones de sensores en `dispose()`

**Archivo:** [movile_app/lib/src/services/speed/speed_measurement_service.dart:133-141 y 167-173](movile_app/lib/src/services/speed/speed_measurement_service.dart)

Hay **dos** métodos de limpieza: `disposeAsync()` cancela `_gpsSub`/`_accelSub`, pero el `dispose()` síncrono (el nombre convencional, p.ej. desde `State.dispose()`) **no los cancela** — solo libera los `ValueNotifier`. Si se llama a `dispose()` sin haber llamado antes a `liveStop()`:

- Las suscripciones de GPS y acelerómetro **siguen activas** → drenaje de batería y fuga de recursos.
- El callback `_onSample` puede dispararse sobre `ValueNotifier`s ya desechados (`instantaneousKmh.value = ...`) → excepción *"A ValueNotifier was used after being disposed"*.

**Solución:** que `dispose()` cancele también las suscripciones (o eliminar la variante síncrona y dejar solo `disposeAsync`). Igualar ambos caminos evita el uso-tras-liberación.

#### 🟡 BUG-12 (Baja) — TOCTOU en `BackgroundTrackingService.startTracking`

**Archivo:** [movile_app/lib/src/services/tracking/background_tracking_service.dart:42-69](movile_app/lib/src/services/tracking/background_tracking_service.dart)

El guard `if (_running) return true;` y la asignación `_running = true` están separados por el `await FlutterForegroundTask.startService(...)`. Dos llamadas casi simultáneas pasan ambas el guard (aún `_running == false`) e invocan `startService` dos veces; la segunda se resuelve con `ServiceAlreadyStartedException` y se adopta el servicio. Funciona, pero es una re-entrada evitable.

**Solución:** marcar un flag `_starting` síncrono antes del `await`, o serializar las llamadas a `startTracking`.

#### 🟡 BUG-13 (Baja) — `speed_sessions.vehicle_id` no verifica pertenencia

**Archivo:** [supabase/migrations/20260522000000_add_speed_sessions.sql:6](supabase/migrations/20260522000000_add_speed_sessions.sql)

La FK `vehicle_id REFERENCES vehicles ON DELETE SET NULL` solo comprueba existencia, no que el vehículo pertenezca al mismo usuario. Un usuario podría asociar su sesión a un `vehicle_id` ajeno. Impacto negligible (los UUID no son enumerables y la lectura de `vehicles` es solo-dueño), pero conviene validar pertenencia si en el futuro se exponen estos datos.

### Condiciones de carrera (actualización)

- `SpeedMeasurementService` fusiona streams de GPS e IMU sobre campos mutables compartidos (`_liveSpeedKmh`, `_liveDistanceM`, `_lastImuTickAt`). Al ejecutarse todo en el isolate principal **no hay carrera de datos real**; el problema relevante es el del ciclo de vida (BUG-11), no la concurrencia.
- `LiveTrackingController`: guards síncronos correctos (`startSession`/`finishSession`), `_ticker` y `_eventSub` cancelados en `dispose`. ✅ Sin carreras.
- Confirmado que `background_tracking_service` solo tiene el TOCTOU menor de BUG-12.

### Código duplicado (añadidos)

- **DUP-6** — Doble método de limpieza (`dispose()` vs `disposeAsync()`) en `SpeedMeasurementService`, con lógica divergente (origen de BUG-11). Unificar.
- **DUP-7** — El patrón "borrar hijos + reinsertar" aparece tanto en las RPC de sesiones (atómico) como en `upsertRoute` (no atómico, BUG-10). Unificar todo bajo RPCs atómicas.

### Resumen de la segunda pasada

| ID | Sev. | Título | Archivo |
|---|---|---|---|
| SEC-11 | 🟠 Media (condicional) | Superadmin curador vía inserts crudos en `auth.users`; posible takeover por email | `20260601000005/006_*.sql` |
| SEC-12 | 🟡 Baja | SQLite local sin cifrar (telemetría/logs/perfil) | `splitway_local_database.dart` |
| SEC-13 | ℹ️ Mitigado | `vehicle-photos` aceptaba SVG (XSS) — corregido después | `20260520000001` → `20260520000003` |
| BUG-10 | 🟠 Media | Reemplazo de sectores no atómico en `upsertRoute` | `supabase_repository.dart` |
| BUG-11 | 🟠 Media | `dispose()` filtra suscripciones de sensores | `speed_measurement_service.dart` |
| BUG-12 | 🟡 Baja | TOCTOU en `startTracking` | `background_tracking_service.dart` |
| BUG-13 | 🟡 Baja | `speed_sessions.vehicle_id` sin validar pertenencia | `20260522000000_add_speed_sessions.sql` |

**Prioridad actualizada (incluyendo ambas pasadas):** SEC-1 → BUG-1 → **SEC-11 (verificar buzón)** → SEC-2 → **BUG-10 / BUG-11** → SEC-3 → resto.

La puntuación global se mantiene en **7.5/10**: los hallazgos nuevos son de severidad media/baja y la mayoría son de robustez/correctitud más que vulnerabilidades explotables remotamente. La excepción a vigilar es SEC-11, cuya severidad depende enteramente de un hecho operativo (¿controla el equipo `splitwayoficial@gmail.com`?) que debe confirmarse.

---

## 10. Correcciones aplicadas (2026-06-11)

Todos los bugs de correctitud y condiciones de carrera (BUG-1…BUG-13) se han corregido siguiendo TDD donde el harness lo permitía. Los hallazgos de seguridad (SEC-*) y la duplicación (DUP-*) **no** se han tocado en esta tanda (quedan como trabajo separado).

### Resumen

| ID | Estado | Fix | Verificación |
|---|---|---|---|
| BUG-1 | ✅ Corregido | Push de rutas usa `updatedAt` (no `createdAt`) vía `SyncPlanner.shouldPush` | `sync_planner_test.dart` (TDD) + suite |
| BUG-2 | ✅ Corregido (rutas) / ⚠️ parcial (sesiones) | Pull de rutas actualiza filas existentes si el remoto es más reciente (`shouldPull`) | `sync_planner_test.dart` |
| BUG-3 | ✅ Corregido | Guard `shouldApplyReconciliationDeletions`: no se borra local si el fetch remoto viene vacío | `sync_planner_test.dart` |
| BUG-4 | ✅ Corregido | RPC de upsert lanzan excepción ante colisión de `id` de otro dueño | Migración (pendiente aplicar) |
| BUG-5 | ✅ Corregido | `set search_path = public` en las dos RPC de upsert | Migración (pendiente aplicar) |
| BUG-6 | ✅ Corregido | `delete-user` purga storage recursivamente (sin doble `list`, cualquier profundidad) | Revisión (Deno no ejecutable aquí) |
| BUG-7 | ✅ Corregido | `LogSanitizer.sanitizeContext` recorre maps/listas anidados + claves sensibles añadidas | `log_sanitizer_test.dart` (TDD) |
| BUG-9 | ✅ Corregido | Eliminada variable muerta `accessToken` en `auth_service` | `flutter analyze` |
| BUG-10 | ✅ Corregido | Nueva RPC atómica `upsert_route_with_sectors`; cliente la usa en vez de delete+insert | Migración + `flutter analyze` |
| BUG-11 | ✅ Corregido | `dispose()` cancela suscripciones de sensores + guard `_disposed` en `_onSample` | `speed_measurement_service_test.dart` (TDD) |
| BUG-12 | ✅ Corregido | Guard `_starting` síncrono antes del `await` en `startTracking` | `background_tracking_service_test.dart` (TDD) |
| BUG-13 | ✅ Corregido | Trigger `enforce_speed_session_vehicle_owner` valida pertenencia del vehículo | Migración (pendiente aplicar) |

### Archivos nuevos

- `movile_app/lib/src/services/sync/sync_planner.dart` — lógica de decisión pura y testeable (BUG-1/2/3).
- `movile_app/test/services/sync/sync_planner_test.dart` — 11 tests.
- `supabase/migrations/20260611000000_harden_upsert_owner_guards.sql` — BUG-4 + BUG-5.
- `supabase/migrations/20260611000001_upsert_route_with_sectors.sql` — BUG-10.
- `supabase/migrations/20260611000002_speed_sessions_vehicle_owner_guard.sql` — BUG-13.

### Verificación

- **Dart**: `flutter analyze lib` sin errores (solo 13 `info` de deprecaciones de `Color` preexistentes en `splitway_map.dart`, ajenas a estos cambios). `flutter test` → **239/239 tests pasan**, incluidos los nuevos escritos en rojo→verde.
- **SQL (3 migraciones)**: escritas siguiendo los patrones ya probados del repo, pero **no ejecutadas** porque el stack local de Supabase requiere Docker (no disponible en este entorno). **Acción requerida:** aplicarlas con `supabase db push` (o `supabase migration up` en local) y validarlas contra la base. El despliegue de la app y de estas migraciones está **acoplado**: `upsertRoute` ahora invoca la RPC `upsert_route_with_sectors`, que debe existir en el proyecto antes de publicar la app.
- **Edge function `delete-user`**: reescrita; Deno no está disponible aquí para test unitario, verificada por revisión.

### Notas y limitaciones

- **BUG-2 (sesiones/free-rides)**: el pull-update completo de sesiones queda pendiente porque la tabla local SQLite `session_runs`/`free_rides` no tiene columna `updated_at` (se versionan por `endedAt`, y las sesiones son prácticamente inmutables). Cerrarlo del todo requiere una migración de esquema local (v11) + cambios de modelo; se deja como follow-up de bajo impacto. El push sí quedó unificado bajo `SyncPlanner.shouldPush`.
- Las RPC de upsert siguen siendo `SECURITY INVOKER` (RLS y el trigger `enforce_official_owner` siguen aplicando) — intencional.

---

## 11. Correcciones de seguridad y dedup (2026-06-11, segunda tanda)

Tras los bugs, se cerraron los hallazgos de seguridad accionables por código y dos duplicaciones de bajo riesgo.

| ID | Estado | Fix | Verificación |
|---|---|---|---|
| SEC-1 | ✅ Corregido | `mapbox-routing` ahora **valida el JWT** (`auth.getUser`) y aplica rate-limit por usuario (RPC `consume_mapbox_quota`, 60/min) | `tsc` n/a (Deno); migración pendiente de aplicar |
| SEC-2 | ✅ Corregido | `app_logs`: CHECKs de longitud (`NOT VALID`) + trigger de throttle por `auth.uid()` (2000/min) | Migración pendiente de aplicar |
| SEC-3 | ✅ Corregido | Helper `authorizeTargetAction`: un `admin` no puede banear/editar/resetear a un `superadmin`, ni a otro `admin` salvo que sea superadmin. Aplicado a `editUserProfile`, `banUser`, `resetUserPassword` | `tsc --noEmit` (exit 0) |
| SEC-4 | ✅ Corregido | Callback OAuth valida el host contra `ADMIN_ALLOWED_REDIRECT_HOSTS` (allowlist opcional vía env) antes de redirigir | `tsc` + lint (0 errores) |
| SEC-5 | ✅ Corregido | `resetUserPassword` deriva el email del `userId` server-side (RPC `find_email_by_user_id`) en vez de confiar en el formulario | `tsc` (exit 0) |
| DUP-4 | ✅ Corregido | CORS centralizado en `supabase/functions/_shared/cors.ts`; lo usan ambas edge functions | revisión |
| DUP-6 | ✅ Corregido | `SpeedMeasurementService.dispose()`/`disposeAsync()` comparten `_closeNotifiers()` | `speed_measurement_service_test.dart` |

### Archivos nuevos / modificados (segunda tanda)

- `supabase/functions/_shared/cors.ts` — CORS compartido (nuevo).
- `supabase/functions/mapbox-routing/index.ts` — validación JWT + cuota (reescrito).
- `supabase/functions/delete-user/index.ts` — usa CORS compartido.
- `supabase/migrations/20260611000003_mapbox_quota.sql` — tabla + RPC de cuota Mapbox (SEC-1).
- `supabase/migrations/20260611000004_app_logs_limits.sql` — límites + throttle de `app_logs` (SEC-2).
- `admin/lib/auth.ts` — helper `authorizeTargetAction` (SEC-3).
- `admin/app/(dashboard)/users/[id]/actions.ts` — guards + email derivado (SEC-3/5).
- `admin/app/auth/callback/route.ts` — allowlist de host (SEC-4).
- `admin/.env.local.example` — documenta `ADMIN_ALLOWED_REDIRECT_HOSTS`.

### No abordado en esta tanda (recomendado como trabajo aparte)

- **SEC-11** (cuenta curadora `splitwayoficial@gmail.com` vía inserts crudos en `auth.users` + posible takeover por email): es **operativo** — requiere confirmar/asegurar el control del buzón Gmail y, opcionalmente, recrear la cuenta vía Admin API. No es un cambio de código aislado seguro de aplicar aquí.
- **SEC-12** (SQLite local sin cifrar): cambiar a SQLCipher es una migración de dependencia con riesgo; se recomienda evaluarlo aparte.
- **DUP-1 / DUP-2 / DUP-3 / DUP-5** (wrapper de server actions y componentes React compartidos): refactor transversal de ~10 ficheros **sin tests** que los respalden. Se deja deliberadamente fuera para no cambiar la firma de las acciones a ciegas; conviene abordarlo con su propia tanda de tests. DUP-1 tiene además valor de seguridad (garantiza el guard), así que es el candidato prioritario.

### Acción de despliegue requerida

Las **5 migraciones** `20260611*` deben aplicarse (`supabase db push`) **junto con** el despliegue de la app y de las edge functions, ya que existe acoplamiento: `upsertRoute` → RPC `upsert_route_with_sectors`, y `mapbox-routing` → RPC `consume_mapbox_quota`. Re-desplegar las edge functions: `supabase functions deploy mapbox-routing delete-user`.

> **Recordatorio de producción:** definir `ADMIN_ALLOWED_REDIRECT_HOSTS` en el entorno del admin para que SEC-4 quede activo (sin él, el comportamiento es el antiguo).

### Verificación contra el proyecto cloud (2026-06-11)

Tras aplicar el usuario las migraciones/edge functions al proyecto `jylteevzapwnovfkxwzc` y arrancar el admin:

- `supabase migration list` → las 5 migraciones `20260611*` constan **aplicadas en remoto** (que `db push` aplicara sin error = SQL válido + objetos creados).
- RPC `upsert_route_with_sectors` (service-role) → `P0001 Not authenticated`: existe y su guard funciona (BUG-10).
- RPC `consume_mapbox_quota` → `23503` violación de FK `mapbox_quota_user_id_fkey`: función + tabla existen, sin persistir fila (SEC-1).
- Callback OAuth con `X-Forwarded-Host: evil.example.com` falsificado (allowlist activa) → redirige a `localhost`, **no** a `evil` → open-redirect cerrado (SEC-4).
- `/login` → 200; `/` sin sesión → 307 → `/login`: la app corre sin romperse con SEC-3/4/5.
- **No exercido:** flujos UI de SEC-3/SEC-5 (detrás de login, sin credenciales en el proyecto prod) — verificados por `tsc` + arranque de la app.

### Adicional: SEC-2 reforzado en cliente

`AppLogger` ahora **trunca** `message`/`error`/`stack_trace` a los mismos topes que los CHECK del servidor (10000/10000/20000) con marcador `…[truncated]`, para que un log legítimo grande se almacene recortado en vez de ser rechazado por la constraint y descartado tras reintentos. Verificado con `app_logger_test.dart` (TDD) — **240/240** tests Flutter pasan.
