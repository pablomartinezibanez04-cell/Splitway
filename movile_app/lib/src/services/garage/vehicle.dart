enum VehicleType {
  car,
  motorcycle,
  bicycle,
  goKart,
  other;

  String get id => name;

  /// Motorized vehicles rotate the recording camera with the GPS course
  /// only: inside a vehicle the phone's compass is unreliable (engine
  /// vibration, body metal) and its orientation is unrelated to the
  /// direction of travel.
  bool get isMotorized => switch (this) {
        VehicleType.car || VehicleType.motorcycle || VehicleType.goKart =>
          true,
        VehicleType.bicycle || VehicleType.other => false,
      };

  static VehicleType fromId(String value) =>
      VehicleType.values.firstWhere(
        (e) => e.id == value,
        orElse: () => VehicleType.other,
      );
}

enum Drivetrain {
  front,
  rear,
  allWheel;

  String get id => name;

  static Drivetrain fromId(String value) =>
      Drivetrain.values.firstWhere(
        (e) => e.id == value,
        orElse: () => Drivetrain.rear,
      );
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.photoUrl,
    this.model,
    this.year,
    this.horsepower,
    this.torqueNm,
    this.weightKg,
    this.drivetrain,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String name;
  final VehicleType type;
  final String? photoUrl;
  final String? model;
  final int? year;
  final int? horsepower;
  final int? torqueNm;
  final int? weightKg;
  final Drivetrain? drivetrain;
  final String? notes;
  final DateTime createdAt;

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      type: VehicleType.fromId(json['type'] as String),
      photoUrl: json['photo_url'] as String?,
      model: json['model'] as String?,
      year: json['year'] as int?,
      horsepower: json['horsepower'] as int?,
      torqueNm: json['torque_nm'] as int?,
      weightKg: json['weight_kg'] as int?,
      drivetrain: json['drivetrain'] == null
          ? null
          : Drivetrain.fromId(json['drivetrain'] as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'type': type.id,
      'photo_url': photoUrl,
      'model': model,
      'year': year,
      'horsepower': horsepower,
      'torque_nm': torqueNm,
      'weight_kg': weightKg,
      'drivetrain': drivetrain?.id,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Vehicle copyWith({
    String? id,
    String? userId,
    String? name,
    VehicleType? type,
    Object? photoUrl = _sentinel,
    Object? model = _sentinel,
    Object? year = _sentinel,
    Object? horsepower = _sentinel,
    Object? torqueNm = _sentinel,
    Object? weightKg = _sentinel,
    Object? drivetrain = _sentinel,
    Object? notes = _sentinel,
    DateTime? createdAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      photoUrl: photoUrl == _sentinel ? this.photoUrl : photoUrl as String?,
      model: model == _sentinel ? this.model : model as String?,
      year: year == _sentinel ? this.year : year as int?,
      horsepower:
          horsepower == _sentinel ? this.horsepower : horsepower as int?,
      torqueNm: torqueNm == _sentinel ? this.torqueNm : torqueNm as int?,
      weightKg: weightKg == _sentinel ? this.weightKg : weightKg as int?,
      drivetrain: drivetrain == _sentinel
          ? this.drivetrain
          : drivetrain as Drivetrain?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static const _sentinel = Object();
}
