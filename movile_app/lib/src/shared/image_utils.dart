import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

const _maxUploadBytes = 1024 * 1024; // 1 MB post-compression ceiling

bool isValidImageHeader(Uint8List bytes) {
  if (bytes.length < 12) {
    return false;
  }
  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }
  // PNG: 89 50 4E 47
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  // WebP: RIFF____WEBP
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  return false;
}

/// Validates the image magic bytes and compresses to WebP.
/// Returns null if the image header is unrecognised or the result exceeds 1 MB.
Future<Uint8List?> compressToWebp(
  Uint8List bytes, {
  int maxWidth = 800,
  int maxHeight = 800,
  int quality = 70,
}) async {
  if (!isValidImageHeader(bytes)) return null;

  final compressed = await FlutterImageCompress.compressWithList(
    bytes,
    minWidth: maxWidth,
    minHeight: maxHeight,
    quality: quality,
    format: CompressFormat.webp,
  );

  final result = Uint8List.fromList(compressed);
  if (result.length > _maxUploadBytes) return null;
  return result;
}
