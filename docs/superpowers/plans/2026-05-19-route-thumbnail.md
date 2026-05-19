# Route Thumbnail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically generate a Mapbox Static API thumbnail for each route and display it in the mosaic grid tile.

**Architecture:** When `SyncService` pushes a route to Supabase, `SupabaseRepository.upsertRoute()` calls `RouteThumbnailService` to download a 200x120 PNG from the Mapbox Static Images API with the route polyline overlaid, uploads it to a private Supabase Storage bucket, and stores a 1-year signed URL in the `thumbnail_url` column. `RouteGridTile` displays it via `Image.network`.

**Tech Stack:** Mapbox Static Images API, Supabase Storage, `http` package, Google Encoded Polyline format, sqflite migration v5.

**Spec:** `docs/superpowers/specs/2026-05-19-route-thumbnail-design.md`

---

### Task 1: Add `thumbnailUrl` to `RouteTemplate` model

**Files:**
- Modify: `packages/splitway_core/lib/src/models/route_template.dart`

- [ ] **Step 1: Add field and constructor parameter**

In `route_template.dart`, add `thumbnailUrl` as an optional field:

```dart
class RouteTemplate {
  const RouteTemplate({
    required this.id,
    required this.name,
    required this.path,
    required this.startFinishGate,
    required this.sectors,
    required this.difficulty,
    required this.createdAt,
    this.description,
    this.locationLabel,
    this.thumbnailUrl,
  });

  final String id;
  final String name;
  final String? description;
  final String? locationLabel;
  final String? thumbnailUrl;
  final List<GeoPoint> path;
  final GateDefinition startFinishGate;
  final List<SectorDefinition> sectors;
  final RouteDifficulty difficulty;
  final DateTime createdAt;
```

- [ ] **Step 2: Update `copyWith`**

Add `thumbnailUrl` parameter. Use a sentinel to allow explicitly setting it to `null` (for invalidation):

```dart
RouteTemplate copyWith({
  String? id,
  String? name,
  String? description,
  String? locationLabel,
  Object? thumbnailUrl = _sentinel,
  List<GeoPoint>? path,
  GateDefinition? startFinishGate,
  List<SectorDefinition>? sectors,
  RouteDifficulty? difficulty,
  DateTime? createdAt,
}) {
  return RouteTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    locationLabel: locationLabel ?? this.locationLabel,
    thumbnailUrl: thumbnailUrl == _sentinel
        ? this.thumbnailUrl
        : thumbnailUrl as String?,
    path: path ?? this.path,
    startFinishGate: startFinishGate ?? this.startFinishGate,
    sectors: sectors ?? this.sectors,
    difficulty: difficulty ?? this.difficulty,
    createdAt: createdAt ?? this.createdAt,
  );
}
```

Add the sentinel at class level (private top-level constant):

```dart
const _sentinel = Object();
```

- [ ] **Step 3: Update `toJson` and `fromJson`**

In `toJson`, add:
```dart
'thumbnailUrl': thumbnailUrl,
```

In `fromJson`, add:
```dart
thumbnailUrl: json['thumbnailUrl'] as String?,
```

- [ ] **Step 4: Run existing tests to verify no regressions**

Run: `cd movile_app && flutter test`
Expected: All existing tests pass (thumbnailUrl defaults to null).

- [ ] **Step 5: Commit**

```bash
git add packages/splitway_core/lib/src/models/route_template.dart
git commit -m "feat(model): add thumbnailUrl field to RouteTemplate"
```

---

### Task 2: Create polyline encoder utility (TDD)

**Files:**
- Create: `packages/splitway_core/lib/src/utils/polyline_encoder.dart`
- Create: `packages/splitway_core/test/utils/polyline_encoder_test.dart`
- Modify: `packages/splitway_core/lib/splitway_core.dart`

- [ ] **Step 1: Write the failing tests**

Create `packages/splitway_core/test/utils/polyline_encoder_test.dart`:

```dart
import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('encodePolyline', () {
    test('encodes single point', () {
      final result = encodePolyline([
        const GeoPoint(latitude: -17.0, longitude: 145.0),
      ]);
      expect(result, isNotEmpty);
    });

    test('encodes known polyline correctly', () {
      // Google's example: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
      final result = encodePolyline([
        const GeoPoint(latitude: 38.5, longitude: -120.2),
        const GeoPoint(latitude: 40.7, longitude: -120.95),
        const GeoPoint(latitude: 43.252, longitude: -126.453),
      ]);
      expect(result, '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    });

    test('returns empty string for empty list', () {
      expect(encodePolyline([]), '');
    });
  });

  group('downsamplePath', () {
    test('returns same list when under maxPoints', () {
      final path = [
        const GeoPoint(latitude: 0, longitude: 0),
        const GeoPoint(latitude: 1, longitude: 1),
      ];
      expect(downsamplePath(path, maxPoints: 80), path);
    });

    test('downsamples to maxPoints keeping first and last', () {
      final path = List.generate(
        200,
        (i) => GeoPoint(latitude: i * 0.01, longitude: i * 0.01),
      );
      final result = downsamplePath(path, maxPoints: 10);
      expect(result.length, 10);
      expect(result.first, path.first);
      expect(result.last, path.last);
    });

    test('returns same list when exactly maxPoints', () {
      final path = List.generate(
        80,
        (i) => GeoPoint(latitude: i * 0.01, longitude: i * 0.01),
      );
      expect(downsamplePath(path, maxPoints: 80), path);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/splitway_core && dart test test/utils/polyline_encoder_test.dart`
Expected: FAIL — functions not found.

- [ ] **Step 3: Implement `polyline_encoder.dart`**

Create `packages/splitway_core/lib/src/utils/polyline_encoder.dart`:

```dart
import '../models/geo_point.dart';

/// Encodes a list of [GeoPoint]s into a Google Encoded Polyline string.
///
/// See: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
String encodePolyline(List<GeoPoint> points) {
  if (points.isEmpty) return '';
  final buf = StringBuffer();
  int prevLat = 0;
  int prevLng = 0;

  for (final point in points) {
    final lat = (point.latitude * 1e5).round();
    final lng = (point.longitude * 1e5).round();
    _encode(lat - prevLat, buf);
    _encode(lng - prevLng, buf);
    prevLat = lat;
    prevLng = lng;
  }
  return buf.toString();
}

void _encode(int value, StringBuffer buf) {
  var v = value < 0 ? ~(value << 1) : (value << 1);
  while (v >= 0x20) {
    buf.writeCharCode((0x20 | (v & 0x1f)) + 63);
    v >>= 5;
  }
  buf.writeCharCode(v + 63);
}

/// Reduces [path] to at most [maxPoints] points using even-interval sampling.
/// Always keeps the first and last point.
List<GeoPoint> downsamplePath(List<GeoPoint> path, {int maxPoints = 80}) {
  if (path.length <= maxPoints) return path;

  final result = <GeoPoint>[path.first];
  final step = (path.length - 1) / (maxPoints - 1);
  for (var i = 1; i < maxPoints - 1; i++) {
    result.add(path[(i * step).round()]);
  }
  result.add(path.last);
  return result;
}
```

- [ ] **Step 4: Export from barrel**

Add to `packages/splitway_core/lib/splitway_core.dart`:

```dart
export 'src/utils/polyline_encoder.dart';
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd packages/splitway_core && dart test test/utils/polyline_encoder_test.dart`
Expected: All 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/splitway_core/lib/src/utils/polyline_encoder.dart \
       packages/splitway_core/test/utils/polyline_encoder_test.dart \
       packages/splitway_core/lib/splitway_core.dart
git commit -m "feat(core): add polyline encoder and path downsampler"
```

---

### Task 3: Create `RouteThumbnailService`

**Files:**
- Create: `movile_app/lib/src/data/services/route_thumbnail_service.dart`

- [ ] **Step 1: Create the service**

Create `movile_app/lib/src/data/services/route_thumbnail_service.dart`:

```dart
import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Downloads a Mapbox Static API image of a route and uploads it to
/// Supabase Storage, returning a signed URL valid for 1 year.
class RouteThumbnailService {
  RouteThumbnailService({
    required SupabaseClient supabase,
    required String mapboxToken,
    http.Client? httpClient,
  })  : _supabase = supabase,
        _mapboxToken = mapboxToken,
        _http = httpClient ?? http.Client();

  final SupabaseClient _supabase;
  final String _mapboxToken;
  final http.Client _http;

  static const _bucket = 'route-thumbnails';
  static const _width = 200;
  static const _height = 120;
  static const _strokeWidth = 3;
  static const _strokeColor = 'e74c3c';
  static const _maxPoints = 80;
  static const _signedUrlExpiry = 365 * 24 * 3600; // 1 year

  /// Generates a thumbnail for [route], uploads it to Supabase Storage,
  /// and returns a 1-year signed URL.
  Future<String> generate(RouteTemplate route, String userId) async {
    // 1. Downsample + encode
    final sampled = downsamplePath(route.path, maxPoints: _maxPoints);
    final polyline = encodePolyline(sampled);
    final encodedPolyline = Uri.encodeComponent(polyline);

    // 2. Build Mapbox Static API URL
    final url = Uri.parse(
      'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static'
      '/path-$_strokeWidth+$_strokeColor-1($encodedPolyline)'
      '/auto/${_width}x$_height'
      '?access_token=$_mapboxToken&padding=20',
    );

    // 3. Download PNG
    final response = await _http.get(url);
    if (response.statusCode != 200) {
      throw Exception(
        'Mapbox Static API error ${response.statusCode}: ${response.body}',
      );
    }

    // 4. Upload to Supabase Storage (upsert)
    final storagePath = '$userId/${route.id}.png';
    await _supabase.storage.from(_bucket).uploadBinary(
          storagePath,
          response.bodyBytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        );

    // 5. Create signed URL (1 year)
    return _supabase.storage
        .from(_bucket)
        .createSignedUrl(storagePath, _signedUrlExpiry);
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd movile_app && flutter analyze lib/src/data/services/route_thumbnail_service.dart`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/data/services/route_thumbnail_service.dart
git commit -m "feat(data): add RouteThumbnailService"
```

---

### Task 4: Local database migration v5

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`

- [ ] **Step 1: Bump schema version and add migration**

In `splitway_local_database.dart`:

Change line 14:
```dart
static const int _schemaVersion = 5;
```

Add after the `if (from < 4 ...)` block (after line 149):

```dart
    if (from < 5 && to >= 5) {
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN thumbnail_url TEXT',
      );
    }
```

- [ ] **Step 2: Run existing tests to verify migration doesn't break**

Run: `cd movile_app && flutter test`
Expected: All existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/data/local/splitway_local_database.dart
git commit -m "feat(db): migration v5 — add thumbnail_url to route_templates"
```

---

### Task 5: Update `LocalDraftRepository` to read/write `thumbnail_url`

**Files:**
- Modify: `movile_app/lib/src/data/repositories/local_draft_repository.dart`

- [ ] **Step 1: Add `thumbnail_url` to `saveRouteTemplate` insert map**

In `saveRouteTemplate()`, add to the map at line 49 (after `'owner_id': _userId,`):

```dart
'thumbnail_url': route.thumbnailUrl,
```

- [ ] **Step 2: Read `thumbnail_url` in `_readRoute`**

In `_readRoute()`, add `thumbnailUrl` to the `RouteTemplate` constructor call at line 112-127:

```dart
    return RouteTemplate(
      id: routeId,
      name: row['name']! as String,
      description: row['description'] as String?,
      path: pathJson
          .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      startFinishGate: GateDefinition.fromJson(gateJson),
      sectors: sectors,
      difficulty: RouteDifficultyX.fromId(row['difficulty']! as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ).toLocal(),
      locationLabel: row['location_label'] as String?,
      thumbnailUrl: row['thumbnail_url'] as String?,
    );
```

- [ ] **Step 3: Run existing tests**

Run: `cd movile_app && flutter test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/data/repositories/local_draft_repository.dart
git commit -m "feat(repo): read/write thumbnail_url in LocalDraftRepository"
```

---

### Task 6: Update `SupabaseRepository` — generate thumbnail on upsert

**Files:**
- Modify: `movile_app/lib/src/data/repositories/supabase_repository.dart`

- [ ] **Step 1: Add `RouteThumbnailService` to constructor**

```dart
import '../services/route_thumbnail_service.dart';

class SupabaseRepository {
  SupabaseRepository(this._client, {this.thumbnailService});

  final SupabaseClient _client;
  final RouteThumbnailService? thumbnailService;
```

- [ ] **Step 2: Change `upsertRoute` to return `RouteTemplate` and generate thumbnail**

Replace the current `upsertRoute` method (lines 23-49):

```dart
  /// Upserts a route template (with sectors) to Supabase.
  /// If [thumbnailUrl] is null and [thumbnailService] is configured,
  /// generates a thumbnail before upserting. Returns the (possibly updated)
  /// route.
  Future<RouteTemplate> upsertRoute(RouteTemplate route) async {
    // Generate thumbnail if missing and service is available
    if (route.thumbnailUrl == null && thumbnailService != null) {
      try {
        final url = await thumbnailService!.generate(route, _uid);
        route = route.copyWith(thumbnailUrl: url);
      } catch (e) {
        // Log but continue — route sync must not fail because of thumbnail
        debugPrint('Thumbnail generation failed: $e');
      }
    }

    await _client.from('route_templates').upsert({
      'id': route.id,
      'owner_id': _uid,
      'name': route.name,
      'description': route.description,
      'path_json': route.path.map((p) => p.toJson()).toList(),
      'start_finish_gate_json': route.startFinishGate.toJson(),
      'difficulty': route.difficulty.id,
      'created_at': route.createdAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'thumbnail_url': route.thumbnailUrl,
    });

    // Delete old sectors and re-insert
    await _client.from('sectors').delete().eq('route_id', route.id);
    if (route.sectors.isNotEmpty) {
      await _client.from('sectors').insert(
        route.sectors.map((s) => {
          'id': s.id,
          'route_id': route.id,
          'order_index': s.order,
          'label': s.label,
          'gate_json': s.gate.toJson(),
        }).toList(),
      );
    }

    return route;
  }
```

Add at top of file:

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 3: Read `thumbnail_url` in `_parseRoute`**

In `_parseRoute()` (line 312), add `thumbnailUrl` to the constructor:

```dart
    return RouteTemplate(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      path: pathList
          .map((e) => GeoPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      startFinishGate: GateDefinition.fromJson(gateMap),
      sectors: sectors,
      difficulty: RouteDifficultyX.fromId(row['difficulty'] as String),
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      thumbnailUrl: row['thumbnail_url'] as String?,
    );
```

- [ ] **Step 4: Verify compilation**

Run: `cd movile_app && flutter analyze`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/repositories/supabase_repository.dart
git commit -m "feat(repo): generate thumbnail in SupabaseRepository.upsertRoute"
```

---

### Task 7: Update `SyncService` to persist thumbnail URL locally

**Files:**
- Modify: `movile_app/lib/src/services/sync/sync_service.dart`

- [ ] **Step 1: Update push loop to save returned route with thumbnail URL**

In `_doSync()`, change the push-routes loop (around line 120-127):

```dart
    // Push local → remote (new or newer locally)
    for (final route in localRoutes) {
      if (route.id == 'demo-oval') continue; // never push demo route
      final remoteUpdated = remoteRouteTs[route.id];
      if (remoteUpdated == null || route.createdAt.isAfter(remoteUpdated)) {
        final updated = await remote.upsertRoute(route);
        // Persist generated thumbnail URL back to local DB
        if (updated.thumbnailUrl != null &&
            updated.thumbnailUrl != route.thumbnailUrl) {
          await local.saveRouteTemplate(updated);
        }
        transferred++;
      }
    }
```

- [ ] **Step 2: Verify compilation**

Run: `cd movile_app && flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/services/sync/sync_service.dart
git commit -m "feat(sync): persist thumbnail URL from upsert back to local DB"
```

---

### Task 8: Wire `RouteThumbnailService` in `app.dart`

**Files:**
- Modify: `movile_app/lib/src/app.dart`

- [ ] **Step 1: Import the service and create it in `_createSyncService`**

Add import:

```dart
import 'data/services/route_thumbnail_service.dart';
```

Update `_createSyncService` (line 77-83):

```dart
  void _createSyncService(SupabaseClient client) {
    RouteThumbnailService? thumbnailService;
    if (widget.config.hasMapbox) {
      thumbnailService = RouteThumbnailService(
        supabase: client,
        mapboxToken: widget.config.mapboxToken!,
      );
    }

    _syncService = SyncService(
      local: _repository,
      remote: SupabaseRepository(client, thumbnailService: thumbnailService),
    );
    _syncService!.startPeriodicSync();
  }
```

- [ ] **Step 2: Verify compilation**

Run: `cd movile_app && flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/app.dart
git commit -m "feat(app): wire RouteThumbnailService into sync pipeline"
```

---

### Task 9: Update `RouteGridTile` to display thumbnail

**Files:**
- Modify: `movile_app/lib/src/features/editor/widgets/route_grid_tile.dart`

- [ ] **Step 1: Replace `Spacer` with thumbnail image**

In `route_grid_tile.dart`, replace `const Spacer(),` (line 83) with:

```dart
              if (route.thumbnailUrl != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        route.thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) {
                          return Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.map_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
```

- [ ] **Step 2: Run existing widget tests**

Run: `cd movile_app && flutter test`
Expected: All tests pass (existing tests create routes with `thumbnailUrl == null`, so they hit the `Spacer` branch).

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/editor/widgets/route_grid_tile.dart
git commit -m "feat(ui): display route thumbnail in RouteGridTile mosaic view"
```

---

### Task 10: Supabase schema migration and Storage bucket

**Files:**
- Supabase dashboard or CLI

- [ ] **Step 1: Add `thumbnail_url` column to `route_templates` table**

Run via Supabase SQL Editor or CLI:

```sql
ALTER TABLE route_templates ADD COLUMN thumbnail_url TEXT;
```

- [ ] **Step 2: Create `route-thumbnails` Storage bucket (private)**

Via Supabase dashboard:
1. Go to Storage → New bucket
2. Name: `route-thumbnails`
3. Public: **OFF** (private)
4. File size limit: 100 KB
5. Allowed MIME types: `image/png`

Or via SQL:

```sql
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('route-thumbnails', 'route-thumbnails', false, 102400, ARRAY['image/png']);
```

- [ ] **Step 3: Add Storage RLS policies**

Allow authenticated users to manage their own thumbnails:

```sql
-- Upload: users can insert into their own folder
CREATE POLICY "Users upload own thumbnails"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'route-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Read: users can read their own thumbnails (needed for signed URLs)
CREATE POLICY "Users read own thumbnails"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'route-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Update: users can overwrite their own thumbnails (for upsert)
CREATE POLICY "Users update own thumbnails"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'route-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Delete: users can delete their own thumbnails
CREATE POLICY "Users delete own thumbnails"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'route-thumbnails'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
```

- [ ] **Step 4: Verify bucket works**

Upload a test PNG via Supabase dashboard to `{your-user-id}/test.png`, then create a signed URL. Verify the URL returns the image.

- [ ] **Step 5: Commit any migration files if using Supabase CLI**

```bash
git add supabase/migrations/
git commit -m "feat(supabase): add thumbnail_url column and route-thumbnails bucket"
```

---

### Task 11: Full integration test

- [ ] **Step 1: Run all tests**

Run: `cd movile_app && flutter test`
Expected: All tests pass.

- [ ] **Step 2: Manual runtime test**

1. Launch the app on a device/emulator with network access.
2. Draw and save a new route.
3. Wait for sync (or trigger manually).
4. Switch to mosaic/grid view on the routes list.
5. Verify the thumbnail appears in the grid tile center.
6. Verify list view (`RouteListTile`) is unaffected.
7. Edit the route path → save → verify thumbnail regenerates on next sync.

- [ ] **Step 3: Verify offline behavior**

1. Turn off network on device.
2. Create a new route.
3. Verify grid tile shows empty spacer (no crash).
4. Turn network back on → wait for sync.
5. Verify thumbnail appears after sync completes.

- [ ] **Step 4: Final commit (if any test fixes needed)**

```bash
git add -A
git commit -m "fix: address integration test findings"
```
