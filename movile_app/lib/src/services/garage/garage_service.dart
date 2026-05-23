import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/garage_repository.dart';
import 'vehicle.dart';

class GarageService extends ChangeNotifier {
  GarageService(GarageRepository repository) : _repository = repository;

  /// Testing-only constructor: creates a [GarageService] pre-populated with a
  /// fixed list of vehicles and no backing repository. Repository methods must
  /// not be called on an instance created this way.
  @visibleForTesting
  GarageService.withVehicles(List<Vehicle> vehicles)
      : _repository = null,
        _vehicles = List.unmodifiable(vehicles);

  final GarageRepository? _repository;

  List<Vehicle> _vehicles = const [];
  List<Vehicle> get vehicles => _vehicles;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> loadVehicles() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _vehicles = await _repository!.getVehicles();
    } catch (e) {
      debugPrint('GarageService.loadVehicles error: $e');
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  Future<Vehicle?> addVehicle({
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
    _error = null;

    try {
      final id = const Uuid().v4();
      final vehicle = await _repository!.createVehicle(
        id: id,
        name: name,
        type: type,
        model: model,
        year: year,
        horsepower: horsepower,
        torqueNm: torqueNm,
        weightKg: weightKg,
        drivetrain: drivetrain,
        notes: notes,
      );
      _vehicles = [vehicle, ..._vehicles];
      notifyListeners();
      return vehicle;
    } catch (e) {
      debugPrint('GarageService.addVehicle error: $e');
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateVehicle(Vehicle vehicle) async {
    _error = null;

    try {
      await _repository!.updateVehicle(vehicle);
      _vehicles = [
        for (final v in _vehicles)
          if (v.id == vehicle.id) vehicle else v,
      ];
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('GarageService.updateVehicle error: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteVehicle(String vehicleId) async {
    _error = null;

    try {
      await _repository!.deleteVehicle(vehicleId);
      _vehicles = [
        for (final v in _vehicles)
          if (v.id != vehicleId) v,
      ];
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('GarageService.deleteVehicle error: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadPhoto(
    String vehicleId,
    Uint8List bytes,
    String extension,
  ) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final photoUrl = await _repository!.uploadPhoto(vehicleId, bytes, extension);
      _vehicles = [
        for (final v in _vehicles)
          if (v.id == vehicleId) v.copyWith(photoUrl: photoUrl) else v,
      ];
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('GarageService.uploadPhoto error: $e');
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _vehicles = const [];
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
