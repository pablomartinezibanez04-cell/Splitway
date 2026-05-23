# Location Search Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a floating search bar to the route editor drawing view so users can search for locations and fly the map camera there.

**Architecture:** New `ForwardGeocodingService` calls Mapbox Forward Geocoding API v6. A `LocationSearchBar` widget with debounced input sits as a `Positioned` overlay on the map `Stack`. On result selection, the existing `FlyToNotifier` animates the camera. A `GeocodingResult` model in `splitway_core` carries name + coordinates.

**Tech Stack:** Flutter, Mapbox Geocoding API v6, `http` package (already a dependency)

---

### Task 1: Add `GeocodingResult` model to `splitway_core`

**Files:**
- Create: `packages/splitway_core/lib/src/models/geocoding_result.dart`
- Modify: `packages/splitway_core/lib/splitway_core.dart`

- [ ] **Step 1: Create the model file**

```dart
// packages/splitway_core/lib/src/models/geocoding_result.dart
import 'geo_point.dart';

class GeocodingResult {
  const GeocodingResult({required this.name, required this.coordinates});

  final String name;
  final GeoPoint coordinates;
}
```

- [ ] **Step 2: Export from barrel file**

In `packages/splitway_core/lib/splitway_core.dart`, add this line after the existing `geo_point.dart` export:

```dart
export 'src/models/geocoding_result.dart';
```

- [ ] **Step 3: Verify it compiles**

Run: `cd movile_app && flutter pub get`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add packages/splitway_core/lib/src/models/geocoding_result.dart packages/splitway_core/lib/splitway_core.dart
git commit -m "feat: add GeocodingResult model to splitway_core"
```

---

### Task 2: Create `ForwardGeocodingService`

**Files:**
- Create: `movile_app/lib/src/services/geocoding/forward_geocoding_service.dart`

- [ ] **Step 1: Create the service**

```dart
// movile_app/lib/src/services/geocoding/forward_geocoding_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';

class ForwardGeocodingService {
  const ForwardGeocodingService({required this.accessToken, http.Client? client})
      : _client = client;

  final String accessToken;
  final http.Client? _client;

  Future<List<GeocodingResult>> search(String query) async {
    if (query.trim().isEmpty) return const [];

    final url = Uri.parse(
      'https://api.mapbox.com/search/geocode/v6/forward'
      '?q=${Uri.encodeComponent(query.trim())}'
      '&limit=5'
      '&access_token=$accessToken',
    );

    try {
      final client = _client ?? http.Client();
      final response = await client.get(url).timeout(const Duration(seconds: 5));
      if (_client == null) client.close();

      if (response.statusCode != 200) return const [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return const [];

      final results = <GeocodingResult>[];
      for (final feature in features) {
        final map = feature as Map<String, dynamic>;
        final properties = map['properties'] as Map<String, dynamic>?;
        final geometry = map['geometry'] as Map<String, dynamic>?;
        if (properties == null || geometry == null) continue;

        final name = properties['full_address'] as String? ??
            properties['name'] as String?;
        final coords = geometry['coordinates'] as List<dynamic>?;
        if (name == null || coords == null || coords.length < 2) continue;

        results.add(GeocodingResult(
          name: name,
          coordinates: GeoPoint(
            latitude: (coords[1] as num).toDouble(),
            longitude: (coords[0] as num).toDouble(),
          ),
        ));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd movile_app && flutter pub get`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/services/geocoding/forward_geocoding_service.dart
git commit -m "feat: add ForwardGeocodingService for Mapbox forward geocoding"
```

---

### Task 3: Add localization strings

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add English strings**

In `movile_app/lib/l10n/app_en.arb`, add these two entries before the closing `}`:

```json
  "editorSearchLocationHint": "Search location...",
  "editorSearchNoResults": "No results found"
```

- [ ] **Step 2: Add Spanish strings**

In `movile_app/lib/l10n/app_es.arb`, add these two entries before the closing `}`:

```json
  "editorSearchLocationHint": "Buscar ubicación...",
  "editorSearchNoResults": "Sin resultados"
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd movile_app && flutter gen-l10n`
Expected: Generates updated `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_es.dart` without errors.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat: add location search localization strings (en/es)"
```

---

### Task 4: Create `LocationSearchBar` widget

**Files:**
- Create: `movile_app/lib/src/features/editor/widgets/location_search_bar.dart`

- [ ] **Step 1: Create the widget file**

```dart
// movile_app/lib/src/features/editor/widgets/location_search_bar.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../services/geocoding/forward_geocoding_service.dart';

class LocationSearchBar extends StatefulWidget {
  const LocationSearchBar({
    super.key,
    required this.accessToken,
    required this.onLocationSelected,
  });

  final String accessToken;
  final ValueChanged<GeoPoint> onLocationSelected;

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final ForwardGeocodingService _service;
  Timer? _debounce;
  List<GeocodingResult> _results = const [];
  bool _loading = false;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _service = ForwardGeocodingService(accessToken: widget.accessToken);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _showResults = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await _service.search(value);
      if (!mounted) return;
      setState(() {
        _results = results;
        _showResults = true;
        _loading = false;
      });
    });
  }

  void _onResultTap(GeocodingResult result) {
    widget.onLocationSelected(result.coordinates);
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _results = const [];
      _showResults = false;
    });
  }

  void _onClear() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _results = const [];
      _showResults = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(28),
          color: theme.colorScheme.surface,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: l.editorSearchLocationHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _onClear,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              isDense: true,
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (_showResults)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l.editorSearchNoResults,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (_, index) {
                            final result = _results[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.place_outlined,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                result.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                              onTap: () => _onResultTap(result),
                            );
                          },
                        ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd movile_app && flutter pub get`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/editor/widgets/location_search_bar.dart
git commit -m "feat: add LocationSearchBar widget with debounced Mapbox search"
```

---

### Task 5: Integrate search bar into `_DrawingView`

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_screen.dart`

- [ ] **Step 1: Add the import**

At the top of `route_editor_screen.dart`, add this import alongside the existing widget imports:

```dart
import 'widgets/location_search_bar.dart';
```

- [ ] **Step 2: Add the `LocationSearchBar` to the `Stack`**

In `_DrawingViewState.build()`, inside the `Stack` children (after the `SplitwayMap` widget and before the existing `Positioned` with the FABs), add:

```dart
if (widget.config.hasMapbox)
  Positioned(
    top: 12,
    left: 12,
    right: 12,
    child: SafeArea(
      child: LocationSearchBar(
        accessToken: widget.config.mapboxToken!,
        onLocationSelected: (point) => _flyToNotifier.flyTo(point),
      ),
    ),
  ),
```

- [ ] **Step 3: Verify it compiles**

Run: `cd movile_app && flutter pub get`
Expected: No errors

- [ ] **Step 4: Manual test**

Run: `cd movile_app && flutter run`
Test the following:
1. Create a new route and enter drawing mode
2. Verify the search bar appears at the top of the map
3. Type a city name (e.g. "Madrid") and verify suggestions appear after a short delay
4. Tap a suggestion and verify the map flies to that location
5. Verify the search field clears and suggestions disappear after selection
6. Verify the clear (X) button works
7. Verify the existing FABs (routing profile, center on user) are still visible and functional
8. Verify drawing on the map still works (tapping, freehand)

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_screen.dart
git commit -m "feat: integrate location search bar into route editor drawing view"
```
