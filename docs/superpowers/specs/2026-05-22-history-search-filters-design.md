# History Search & Filters — Design

**Date:** 2026-05-22
**Scope:** `movile_app/lib/src/features/history/history_screen.dart`
**Goal:** Add a persistent search bar plus a filters bottom sheet to the History screen, applying to both the "Todo" and "Velocidad" tabs.

## Motivation

The History screen currently shows a chronologically sorted list with paginated loading (`_pageSize = 30`) and a single SegmentedButton (Todo / Velocidad). With time, users accumulate enough sessions, free rides, and speed sessions that scrolling becomes the only way to find a specific entry. We want quick text search and a small set of structured filters so a user can answer questions like:

- "Show me only sessions in vehicle X from the last 30 days."
- "Free rides with max speed above 100 km/h."
- "All entries whose name contains 'jarama'."

## UX

### Top of the screen layout

```
AppBar  [☰  Historial         ↻]
─────────────────────────────────
[ 🔍  Buscar...            ✕ ]  [ ⚙ ]   ← search row (always visible)
[ chip: Coche A ✕ ] [ chip: Últ. 30d ✕ ] … (horizontal scroll, only if active)
[ Todo | Velocidad ]                        ← existing SegmentedButton
─────────────────────────────────
list / empty state
```

- **Search field:** persistent below the AppBar. Outlined `TextField` with leading lupa icon and a trailing `✕` that clears the text (visible only when not empty). Hint: `historySearchHint` ("Buscar por nombre…").
- **Filter button:** `IconButton` with `Icons.tune`. When `filters.activeCount > 0`, an outlined badge with the count is shown next to the icon.
- **Active filter chips row:** horizontally scrollable `Wrap`/`ListView` of `InputChip`s, one per active filter, each with a `✕` action that clears that specific filter. The row is hidden when no filters are active.

### Filters bottom sheet

`showModalBottomSheet` (scrollable, `useSafeArea: true`). Title bar: "Filtros" + close (`X`). Sections, all collapsible-by-default visible but contained in a scroll view:

1. **Tipo de entrada** (visible only when current tab = Todo).
   - Two `FilterChip`s: "Sesión" and "Free ride". Multi-select. None selected = both shown.
2. **Vehículo.**
   - One `ChoiceChip` per vehicle in `garageService.vehicles`, plus a "Sin vehículo" chip (matches entries with `vehicleId == null`). Multi-select. None selected = all shown.
3. **Rango de fechas.**
   - Preset row of `OutlinedButton`s: "Últimos 7 días", "Últimos 30 días", "Este año", "Personalizado…".
   - "Personalizado…" opens the native `showDateRangePicker`.
   - Selected preset/range displayed as a read-only summary line below the buttons.
4. **Velocidad máxima ≥** (visible in both tabs).
   - A single numeric `TextField` (keyboardType = number) with the unit suffix from `settingsController.unitSystem` (km/h or mph). Stored internally as m/s.
5. **Distancia mínima ≥** (visible only when current tab = Todo).
   - Numeric `TextField` with unit suffix (km or mi). Stored internally as meters.

Footer: full-width row with `TextButton("Limpiar")` and `FilledButton("Aplicar")`. "Limpiar" clears the working draft; "Aplicar" commits it to state and closes the sheet. Tapping outside or back also commits the working draft (matching Material 3 bottom sheet expectations).

### Empty results

When the resulting list is empty *and* any search/filter is active, show `EmptyState`:

- Icon: `Icons.search_off`.
- Title: `historyFilteredEmptyTitle` ("Sin resultados").
- Action button below: `historyFilteredEmptyAction` ("Limpiar filtros") → clears search + filters.

When no filters are active and the list is empty, the existing `historyNoEntriesTitle/Message` empty state is preserved.

## Behavior

### Tabs

- The search field, filter button, chips row, and the underlying `_HistoryFilters` are **shared** across both tabs.
- Filter sections that don't apply to the current tab are hidden in the sheet (Tipo de entrada and Distancia mínima are hidden in the Velocidad tab).
- Hidden filter values are still kept in state, so toggling back to Todo restores them.

### Loading strategy

The repository is not modified. Filtering and search are done client-side:

- **Tab Todo, no active filters and empty search:** keep current paginated behavior (`getAllSessions`/`getAllFreeRides` with `limit: _pageSize, offset:_*Offset`) and the "load more" sentinel.
- **Tab Todo, any filter or non-empty search active:** load the full set once via `getAllSessions(limit: 1000, offset: 0)` and `getAllFreeRides(limit: 1000, offset: 0)`, hide the load-more sentinel, and run the filter in memory. On the first transition from paginated → filtered, set a `_fullyLoaded` flag so subsequent filter edits don't refetch. When all filters clear, restore the paginated state on the next reload.
- **Tab Velocidad:** already loads everything via `listForUser`; just filter in memory.

The 1000-entry cap is a defensive ceiling; realistic per-user counts are far below this. If it ever becomes a problem we'll push filtering into the repository.

### Search semantics

- Case-insensitive, diacritics-insensitive substring match (folds via `String.toLowerCase()` + a small `_removeDiacritics` helper).
- The fields searched per entry:
  - Session: `routes[s.routeTemplateId]?.name`.
  - Free ride: `ride.name` (falls back to the localized free-ride label so users can still search by it).
  - Speed: `s.name`.
- Debounce: 250 ms after the user stops typing before the list is recomputed. The chips/filter changes are immediate (no debounce).

### Filter semantics

For a candidate entry to pass it must satisfy *all* active filter groups (AND across groups, OR within a group):

- **Kind:** entry's kind ∈ selected set. Speed entries are out of scope for this filter (only visible in Velocidad tab).
- **Vehicle:** `entry.vehicleId ∈ selected set` (where `null` matches the "Sin vehículo" pseudo-id).
- **Date range:** `entry.date` is within `[range.start, range.end]` inclusive (end normalized to end-of-day).
- **Min max-speed:** session/free-ride `maxSpeedMps >= threshold`; speed session `results[SpeedMetric.topSpeed] >= threshold` (m/s).
- **Min distance:** session `totalDistanceMeters >= threshold`; free-ride `totalDistanceMeters >= threshold`. (Speed sessions don't expose a distance; this filter is not applied to them — and the UI hides it in the Velocidad tab anyway.)

### Chip labels

Active filter chips are localized:

- Kind: "Sesión" / "Free ride".
- Vehicle: when exactly one vehicle is selected, the chip shows that vehicle's name (or `historyNoVehicle` for the null bucket). When more than one is selected, a single aggregated chip "Vehículos (N)" is shown.
- Date range: preset name when one of the presets is active ("Últ. 30d"), otherwise `"d MMM – d MMM"` from `DateFormat`.
- Min max-speed: `"≥ 120 km/h"` (unit-aware).
- Min distance: `"≥ 5 km"` (unit-aware).

## Data model

A private value class lives next to the screen state:

```dart
enum _EntryKind { session, freeRide }

class _HistoryFilters {
  const _HistoryFilters({
    this.query = '',
    this.kinds = const <_EntryKind>{},
    this.vehicleIds = const <String?>{},
    this.dateRange,
    this.minMaxSpeedMps,
    this.minDistanceMeters,
  });

  final String query;
  final Set<_EntryKind> kinds;
  final Set<String?> vehicleIds;       // null sentinel = "Sin vehículo"
  final DateTimeRange? dateRange;
  final double? minMaxSpeedMps;
  final double? minDistanceMeters;

  bool get isEmpty =>
      query.isEmpty &&
      kinds.isEmpty &&
      vehicleIds.isEmpty &&
      dateRange == null &&
      minMaxSpeedMps == null &&
      minDistanceMeters == null;

  int get activeCount; // excludes query (query has its own UI)

  _HistoryFilters copyWith({ ... });
  _HistoryFilters clear();
}
```

The `_HistoryScreenState` gains:

```dart
_HistoryFilters _filters = const _HistoryFilters();
final TextEditingController _searchCtrl = TextEditingController();
Timer? _searchDebounce;
bool _fullyLoaded = false;
```

Filtering is encapsulated in two pure helpers:

```dart
List<_HistoryEntry> _applyFilters(List<_HistoryEntry> src);
List<SpeedSession> _applySpeedFilters(List<SpeedSession> src);
```

These run on every `build` (cheap, list sizes are small). No memoization needed at this point.

## Localization

New ARB keys to add in both `app_en.arb` and `app_es.arb` (plus the generated `.dart`):

| key                              | en                            | es                              |
|----------------------------------|-------------------------------|---------------------------------|
| historySearchHint                | Search…                       | Buscar…                         |
| historyFiltersTitle              | Filters                       | Filtros                         |
| historyFiltersOpen               | Open filters                  | Abrir filtros                   |
| historyFiltersApply              | Apply                         | Aplicar                         |
| historyFiltersClear              | Clear                         | Limpiar                         |
| historyFilterKindLabel           | Type                          | Tipo                            |
| historyFilterKindSession         | Session                       | Sesión                          |
| historyFilterKindFreeRide        | Free ride                     | Free ride                       |
| historyFilterVehicleLabel        | Vehicle                       | Vehículo                        |
| historyNoVehicle                 | No vehicle                    | Sin vehículo                    |
| historyFilterDateRangeLabel      | Date range                    | Rango de fechas                 |
| historyDateLast7Days             | Last 7 days                   | Últimos 7 días                  |
| historyDateLast30Days            | Last 30 days                  | Últimos 30 días                 |
| historyDateThisYear              | This year                     | Este año                        |
| historyDateCustom                | Custom…                       | Personalizado…                  |
| historyFilterMinMaxSpeedLabel    | Min max speed                 | Velocidad máx. mínima           |
| historyFilterMinDistanceLabel    | Min distance                  | Distancia mínima                |
| historyFilterMinMaxSpeedChip     | ≥ {value}                     | ≥ {value}                       |
| historyFilterMinDistanceChip     | ≥ {value}                     | ≥ {value}                       |
| historyFilterVehicleChipMany     | Vehicles ({count})            | Vehículos ({count})             |
| historyFilteredEmptyTitle        | No matches                    | Sin resultados                  |
| historyFilteredEmptyAction       | Clear filters                 | Limpiar filtros                 |

## Edge cases

- **Garage empty:** the Vehículo section shows only the "Sin vehículo" chip.
- **Vehicle deleted between selection and filtering:** the missing id is silently dropped from `vehicleIds` on the next build (no "deleted vehicle" chip).
- **Numeric inputs:** non-parseable text disables the corresponding filter (treated as `null`).
- **Date range end vs start:** the picker enforces `end >= start`; we normalize end to 23:59:59 before comparing.
- **Repository updates while filtered:** the existing `repository.changes` debounced reload still fires; we re-run `_load()`, which respects `_fullyLoaded` and reissues a full fetch if any filter is active.

## Testing

Widget tests in `movile_app/test/features/history/history_screen_search_test.dart`:

1. Typing in the search field hides non-matching entries across all three kinds (after the 250 ms debounce).
2. Applying a vehicle filter from the bottom sheet reduces the list to entries with that `vehicleId`.
3. Applying min-distance filter (with metric unit) excludes shorter rides.
4. Clearing all filters via the empty-state action restores the full list and re-enables pagination.
5. Switching from Todo to Velocidad keeps the search text but hides "Tipo" and "Distancia mínima" sections in the sheet.

Tests use the existing in-memory `LocalDraftRepository` test double and a fake `SpeedRepository`.

## Out of scope

- Saving filter presets across app launches.
- Server-side filtering or repository-level `where` parameters.
- Sorting controls (kept as descending by date only).
- Filtering on lap-level data (best lap time, sector times).
