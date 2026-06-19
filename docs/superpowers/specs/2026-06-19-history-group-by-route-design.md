# Agrupar por ruta en el historial

**Fecha:** 2026-06-19
**Estado:** Aprobado (diseño)

## Objetivo

Añadir en la hoja de filtros del historial una opción para **agrupar por ruta**.
Cuando está activa, la lista principal deja de mostrar sesiones individuales y
muestra una fila por ruta. Al tocar una ruta se entra a una pantalla con la
lista de todas las veces que se ha corrido esa ruta en concreto.

## Comportamiento

- Un interruptor **"Agrupar por ruta"** en la hoja de filtros
  (`history_filters_sheet.dart`), visible **solo en la pestaña principal** (no en
  la pestaña Velocidad, igual que el filtro de tipo de entrada).
- Cuando está activo, en la pestaña principal:
  - La lista muestra **una fila por ruta** en lugar de sesiones individuales.
  - Las **rutas libres** (free rides) se agrupan todas en una fila final
    llamada **"Rutas libres"**.
  - Al **tocar una fila** se navega a una pantalla que lista todas las
    sesiones / rutas libres de ese grupo, usando las tarjetas actuales
    (`_SessionTile` / `_FreeRideTile`). Desde ahí se entra al detalle de cada
    sesión como ahora.
  - Los **demás filtros** (vehículo, fecha, tipo, búsqueda, distancia mínima)
    se aplican **antes** de agrupar: solo se agrupa lo que ha pasado los
    filtros.
- En la pestaña Velocidad el modo agrupado se ignora (las sesiones de velocidad
  no tienen ruta).

## Fila de ruta (lista principal agrupada)

- **Título:** nombre de la ruta. Si la ruta ya no existe → "Ruta eliminada".
  Para el grupo de free rides → "Rutas libres".
- **Subtítulo:** número de veces corrida + última vez.
  Ej: *"5 sesiones · última 12 jun 2026"*.
- **Orden:** por la sesión más reciente de cada grupo, descendente (la ruta con
  la sesión más reciente arriba). El grupo "Rutas libres" se ordena por la misma
  regla (su entrada más reciente), no se fuerza al final.
- Icono de ruta a la izquierda, chevron a la derecha (consistente con las
  tarjetas actuales).

## Cambios técnicos

### `history_filters.dart`
- Añadir campo `bool groupByRoute` (por defecto `false`) a `HistoryFilters`.
- Soportarlo en `copyWith`.
- **No** se incluye en `activeCount` (es un modo de vista, no un filtro que
  oculta datos), y `isEmpty`/`activeCount` mantienen su semántica actual.
- Carga: el agrupado necesita ver todas las entradas para contar
  correctamente. La pantalla fuerza `_loadAll()` cuando `groupByRoute` está
  activo, igual que hace cuando hay filtros activos (ver `history_screen.dart`
  abajo), sin cambiar la semántica de `isEmpty`.

### `history_filters_sheet.dart`
- Añadir un `SwitchListTile` "Agrupar por ruta" cerca de la cabecera, visible
  solo cuando `!isSpeedTab`.

### `history_screen.dart`
- Cuando `groupByRoute` está activo y estamos en la pestaña principal:
  - Forzar carga completa (`_loadAll`) para contar correctamente — tratar
    `groupByRoute` activo igual que "filtros activos" en `_onFiltersChanged` y
    en el listener de cambios del repositorio.
  - Agrupar las entradas ya filtradas por `routeTemplateId`; las free rides van
    a un grupo sintético "Rutas libres".
  - Calcular por grupo: número de entradas y fecha de la más reciente.
  - Renderizar tiles de grupo (`ListTile` con icono de ruta, título, subtítulo
    contador, chevron).
- Mostrar un **chip eliminable** "Agrupado por ruta" en la fila de chips
  activos (`_buildActiveFilterChips`) para poder desactivarlo rápido, aunque no
  cuente en el badge numérico.
- Nueva pantalla `RouteSessionsScreen` (en el mismo archivo, para reutilizar
  `_SessionTile`/`_FreeRideTile`): recibe el título del grupo y la lista de
  `_HistoryEntry` y los renderiza con las tarjetas actuales.

### i18n (`app_es.arb` / `app_en.arb` + regenerar)
- Label del interruptor: "Agrupar por ruta" / "Group by route".
- Nombre del grupo de free rides: "Rutas libres" / "Free rides".
- Subtítulo contador: ej. plural "{count} sesiones · última {date}".
- Título de la pantalla de sesiones de una ruta (usa el nombre de la ruta).
- Label del chip activo: "Agrupado por ruta" / "Grouped by route".

## Tests
- `history_filters_test.dart`: `groupByRoute` en `copyWith`, valor por defecto,
  que no altera `activeCount`.
- Test de widget para el historial agrupado: con varias sesiones de dos rutas
  + una free ride, verificar que aparecen las filas de grupo con el contador
  correcto y que al tocar se navega a la lista de sesiones de esa ruta.

## Fuera de alcance (YAGNI)
- Mejor vuelta por ruta en la fila (descartado en brainstorming).
- Agrupar en la pestaña Velocidad.
- Estadísticas agregadas por ruta más allá del contador y la última fecha.
</content>
</invoke>
