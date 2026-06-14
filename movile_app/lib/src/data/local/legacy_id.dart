import 'dart:convert';

import 'package:crypto/crypto.dart';

final RegExp _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Deterministically maps a legacy text id to a UUID.
///
/// Mirrors, byte for byte, the `pg_temp.legacy_id_to_uuid` helper from the
/// Supabase migration `20260601000004_text_ids_to_uuid.sql`: valid UUIDs pass
/// through unchanged, while any other string (e.g. `route-1781259371777430`)
/// is md5-hashed and reshaped into the 8-4-4-4-12 UUID layout.
///
/// Because the transformation is identical to the server's, an id rewritten
/// locally lands on the exact UUID the server migration already produced for
/// the same row — so existing routes/sessions reconcile on sync instead of
/// duplicating.
String legacyIdToUuid(String id) {
  if (_uuidRe.hasMatch(id)) return id;
  final h = md5.convert(utf8.encode(id)).toString(); // 32 lowercase hex chars
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20, 32)}';
}
