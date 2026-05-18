# Route Thumbnail — Design Spec

**Date:** 2026-05-19  
**Branch:** feat/routes-list-screen  
**Status:** Approved

---

## Overview

Generate a small map image (mapa real con la ruta encima) for each `RouteTemplate` automatically when the route is saved. The thumbnail is stored in Supabase Storage and displayed in the center of each `RouteGridTile` (mosaic view only). The list view (`RouteListTile`) is unaffected.

---

## Data Model

### `RouteTemplate` (splitway_core)

Add optional field:

```dart
final String? thumbnailUrl;
```

Serialization: `thumbnail_url` key in JSON/SQLite/Supabase. Null means no thumbnail yet.

### Local SQLite — migration v4

```sql
ALTER TABLE route_templates ADD COLUMN thumbnail_url TEXT;
```

### Supabase Postgres

```sql
ALTER TABLE route_templates ADD COLUMN thumbnail_url TEXT;
```

### Supabase Storage

- Bucket: `route-thumbnails`  
- Access: **public** (URLs used directly in `Image.network`)  
- Path pattern: `{userId}/{routeId}.png`  
- Upsert on regeneration (overwrite existing file)

---

## Thumbnail Generation

### Image spec

| Parameter | Value |
|-----------|-------|
| Map style | `mapbox/outdoors-v12` |
| Size | `200x120` (no `@2x`) |
| Padding | `20` px all sides |
| Route stroke | width `3`, color `#e74c3c`, opacity `1` |
| Estimated file size | ~15–25 KB |

### Polyline encoding

- Downsample `route.path` to ≤ 80 points before encoding (evenly spaced sampling).
- Encode as Google Encoded Polyline format.
- Embed in URL as: `path-3+e74c3c-1({encodedPolyline})`.
- Camera: `auto` (Mapbox fits bounding box automatically).

Full URL pattern:
```
https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/
  path-3+e74c3c-1({encodedPolyline})/auto/200x120
  ?access_token={MAPBOX_TOKEN}&padding=20
```

---

## `RouteThumbnailService`

**Location:** `movile_app/lib/src/data/services/route_thumbnail_service.dart`

**Responsibilities:**
1. Downsample path to ≤ 80 points.
2. Encode polyline and build Mapbox Static API URL.
3. `GET` the URL → receive PNG bytes.
4. Upload bytes to Supabase Storage at `{userId}/{routeId}.png` (upsert).
5. Return the public Storage URL.

**Signature:**
```dart
class RouteThumbnailService {
  RouteThumbnailService({required SupabaseClient supabase, required String mapboxToken});

  Future<String> generate(RouteTemplate route, String userId);
}
```

**Error handling:** Any failure (network, API error, Storage error) throws an exception. The caller (`SupabaseRepository`) catches it and logs — the route is still saved without a thumbnail. Retry happens on the next sync when `thumbnailUrl` is still null.

---

## Repository Integration

**`SupabaseRepository.upsertRouteTemplate()`:**

```
if (route.thumbnailUrl == null) {
  try {
    final url = await _thumbnailService.generate(route, currentUserId);
    route = route.copyWith(thumbnailUrl: url);
  } catch (_) { /* log, continue without thumbnail */ }
}
// upsert route (now with thumbnailUrl if generation succeeded)
```

After upsert, also update `thumbnail_url` in the local SQLite via `LocalDraftRepository`.

---

## Thumbnail Invalidation

When the user edits the path of an existing route, `RouteEditorController` sets `thumbnailUrl = null` on the working copy before calling save. This ensures the service regenerates the image on next sync.

Path change detection: the controller already tracks drawing state — any modification to `route.path` during editing triggers the nullification.

---

## `RouteGridTile` changes

Replace the current `Spacer()` with:

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
          loadingBuilder: (context, child, progress) =>
            progress == null ? child : _thumbnailPlaceholder(context),
        ),
      ),
    ),
  )
else
  const Spacer(),
```

`_thumbnailPlaceholder` returns a `Container` filled with `theme.colorScheme.surfaceContainerHighest`.

`RouteListTile` — **no changes**.

---

## Offline behaviour

- Thumbnail generation requires connectivity (Supabase Storage upload).
- If the device is offline when saving, `thumbnailUrl` stays null; the tile shows the existing empty spacer.
- On next successful sync with Supabase (`upsertRouteTemplate`), the thumbnail is generated automatically.

---

## Out of scope

- Thumbnail for `RouteListTile`
- Manual thumbnail regeneration button
- Retry queue for failed generations
- Thumbnail deletion when a route is deleted (future cleanup task)
