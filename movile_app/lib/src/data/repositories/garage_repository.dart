import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/garage/vehicle.dart';
import '../../services/logging/app_logger.dart';
import '../../services/logging/http_logging.dart';

class GarageRepository {
  GarageRepository(this._client);

  final SupabaseClient _client;

  static const _photoBucket = 'vehicle-photos';
  static const _signedUrlExpiry = 365 * 24 * 3600; // 1 year

  String get _uid => _client.auth.currentUser!.id;

  Future<List<Vehicle>> getVehicles() async {
    final response = await logSupabase(
      'garage.getVehicles',
      () => _client
          .from('vehicles')
          .select()
          .eq('user_id', _uid)
          .order('created_at', ascending: false),
    );
    return (response as List<dynamic>)
        .map((e) => Vehicle.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Vehicle> createVehicle({
    required String id,
    required String name,
    required VehicleType type,
    String? model,
    int? year,
    int? horsepower,
    int? torqueNm,
    int? weightKg,
    Drivetrain? drivetrain,
    String? notes,
  }) async {
    final data = {
      'id': id,
      'user_id': _uid,
      'name': name,
      'type': type.id,
      'model': model,
      'year': year,
      'horsepower': horsepower,
      'torque_nm': torqueNm,
      'weight_kg': weightKg,
      'drivetrain': drivetrain?.id,
      'notes': notes,
    };
    final response = await logSupabase(
      'garage.createVehicle',
      () => _client.from('vehicles').insert(data).select().single(),
    );
    return Vehicle.fromJson(response);
  }

  Future<void> updateVehicle(Vehicle vehicle) async {
    await logSupabase(
      'garage.updateVehicle',
      () => _client.from('vehicles').update({
        'name': vehicle.name,
        'type': vehicle.type.id,
        'model': vehicle.model,
        'year': vehicle.year,
        'horsepower': vehicle.horsepower,
        'torque_nm': vehicle.torqueNm,
        'weight_kg': vehicle.weightKg,
        'drivetrain': vehicle.drivetrain?.id,
        'notes': vehicle.notes,
        'photo_url': vehicle.photoUrl,
      }).eq('id', vehicle.id).eq('user_id', _uid),
    );
  }

  Future<void> deleteVehicle(String vehicleId) async {
    try {
      final prefix = '$_uid/$vehicleId/';
      final objects =
          await _client.storage.from(_photoBucket).list(path: '$_uid/$vehicleId');
      for (final obj in objects) {
        await _client.storage
            .from(_photoBucket)
            .remove(['$prefix${obj.name}']);
      }
    } catch (e, st) {
      // Ignore storage errors — the vehicle record is the source of truth.
      AppLogger.maybeInstance?.warning(
        'supabase',
        'garage.deleteVehicle photos cleanup failed',
        error: e,
        stackTrace: st,
      );
    }
    await logSupabase(
      'garage.deleteVehicle',
      () => _client
          .from('vehicles')
          .delete()
          .eq('id', vehicleId)
          .eq('user_id', _uid),
    );
  }

  Future<String> uploadPhoto(
    String vehicleId,
    Uint8List bytes,
    String extension,
  ) async {
    try {
      final old = await _client.storage
          .from(_photoBucket)
          .list(path: '$_uid/$vehicleId');
      if (old.isNotEmpty) {
        await _client.storage.from(_photoBucket).remove(
              old.map((o) => '$_uid/$vehicleId/${o.name}').toList(),
            );
      }
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'supabase',
        'garage.uploadPhoto cleanup failed',
        error: e,
        stackTrace: st,
      );
    }

    final path = '$_uid/$vehicleId/photo.$extension';
    await logSupabase(
      'garage.uploadPhoto.upload',
      () => _client.storage.from(_photoBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$extension',
            ),
          ),
    );
    final signedUrl = await logSupabase(
      'garage.uploadPhoto.signedUrl',
      () => _client.storage
          .from(_photoBucket)
          .createSignedUrl(path, _signedUrlExpiry),
    );

    await logSupabase(
      'garage.uploadPhoto.update',
      () => _client.from('vehicles').update({
        'photo_url': signedUrl,
      }).eq('id', vehicleId).eq('user_id', _uid),
    );

    return signedUrl;
  }
}
