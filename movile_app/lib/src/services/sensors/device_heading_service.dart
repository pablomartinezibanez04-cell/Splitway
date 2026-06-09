import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Fuses accelerometer (gravity) and magnetometer readings into a smoothed
/// magnetic compass heading.
///
/// The heading is reported in degrees clockwise from magnetic north, in the
/// range `[0, 360)`. Matches the convention used by Mapbox's camera bearing
/// and by `TelemetryPoint.bearingDeg`, so the value can be fed directly into
/// `flyTo(bearing: …)`.
///
/// The algorithm mirrors Android's `SensorManager.getRotationMatrix` /
/// `getOrientation`: it builds an East–North–Up frame from the two raw
/// vectors via cross products, then extracts the rotation around the world
/// Z axis (azimuth).
///
/// A low-pass filter that respects the circular nature of bearings is
/// applied so the camera doesn't jitter from sensor noise.
class DeviceHeadingService {
  DeviceHeadingService({this.smoothing = 0.18});

  /// Low-pass smoothing factor in `(0, 1]`. Higher = more responsive but
  /// noisier. `0.18` lets the heading catch up within ~1 s of a quick turn.
  final double smoothing;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  final StreamController<double> _controller =
      StreamController<double>.broadcast();

  /// Stream of smoothed magnetic headings (degrees, `[0, 360)`).
  Stream<double> get headingStream => _controller.stream;

  double? _lastHeadingDeg;

  /// Last heading actually emitted to the stream / returned by
  /// [currentHeadingDeg]. Updated only when the smoothed heading diverges
  /// from this value by at least [_kEmissionThresholdDeg].
  double? _lastEmittedDeg;

  /// Minimum angular change (degrees) from the last emitted heading before
  /// a new value is pushed to the stream. Prevents vibration-induced
  /// micro-drift from accumulating into visible map rotation.
  static const double _kEmissionThresholdDeg = 1.5;

  /// Most recent stable heading, or null if the sensors haven't both
  /// emitted yet.
  double? get currentHeadingDeg => _lastEmittedDeg;

  // Latest raw samples.
  double _ax = 0, _ay = 0, _az = 0;
  double _mx = 0, _my = 0, _mz = 0;
  bool _hasAccel = false;
  bool _hasMag = false;
  bool _running = false;

  // Exponentially averaged gravity vector. Filters out high-frequency
  // vibration (e.g. car engine on a phone mount) that would otherwise
  // cause the computed "horizontal" plane — and thus the heading — to
  // wobble and slowly drift.
  double _gx = 0, _gy = 0, _gz = 0;
  bool _hasGravity = false;
  static const double _kGravitySmoothing = 0.025;

  /// Subscribe to the sensors. Safe to call repeatedly — subsequent calls
  /// are a no-op while already running.
  void start() {
    if (_running) return;
    _running = true;
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((e) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
      _hasAccel = true;
      if (!_hasGravity) {
        _gx = _ax;
        _gy = _ay;
        _gz = _az;
        _hasGravity = true;
      } else {
        _gx += _kGravitySmoothing * (_ax - _gx);
        _gy += _kGravitySmoothing * (_ay - _gy);
        _gz += _kGravitySmoothing * (_az - _gz);
      }
      _emit();
    }, onError: (_) {});
    _magSub = magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((e) {
      _mx = e.x;
      _my = e.y;
      _mz = e.z;
      _hasMag = true;
      _emit();
    }, onError: (_) {});
  }

  /// Cancel sensor subscriptions. The next [start] re-subscribes.
  void stop() {
    _running = false;
    _accelSub?.cancel();
    _magSub?.cancel();
    _accelSub = null;
    _magSub = null;
    _hasAccel = false;
    _hasMag = false;
    _hasGravity = false;
    _lastEmittedDeg = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }

  void _emit() {
    if (!_hasAccel || !_hasMag) return;
    final raw = _computeHeading();
    if (raw == null) return;
    final smoothed = _smooth(raw);
    _lastHeadingDeg = smoothed;
    final emitted = _lastEmittedDeg;
    if (emitted == null ||
        angularDifferenceDeg(smoothed, emitted).abs() >=
            _kEmissionThresholdDeg) {
      _lastEmittedDeg = smoothed;
      if (!_controller.isClosed) _controller.add(smoothed);
    }
  }

  /// Computes the magnetic azimuth in degrees from the latest raw samples.
  /// Returns null when the readings are degenerate (zero gravity / no
  /// magnetic field), which happens during free-fall or strong interference.
  double? _computeHeading() {
    // Use the averaged gravity vector instead of the raw accelerometer to
    // filter out high-frequency vibration (car engine, rough road, etc.).
    final ax = _gx, ay = _gy, az = _gz;
    // East = magnetic × gravity. In device frame this vector points east.
    final hx = _my * az - _mz * ay;
    final hy = _mz * ax - _mx * az;
    final hz = _mx * ay - _my * ax;
    final normH = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (normH < 0.1) return null;
    final hxN = hx / normH;
    final hyN = hy / normH;
    // North = gravity × East. Lies in the horizontal plane, pointing north.
    // We only need the device-Y component of North to compute the azimuth,
    // so we skip the device-X / device-Z components of the cross product.
    final normA = math.sqrt(ax * ax + ay * ay + az * az);
    if (normA < 0.1) return null;
    final axN = ax / normA;
    final azN = az / normA;
    final myN = azN * hxN - axN * (hz / normH);
    // Azimuth = atan2(east_y, north_y) — the rotation around world Z that
    // maps the device's +Y axis (top of screen) onto the horizontal plane.
    var deg = math.atan2(hyN, myN) * 180.0 / math.pi;
    if (deg < 0) deg += 360;
    return deg;
  }

  /// Circular low-pass filter that always picks the shorter arc between
  /// the current and the new heading, so wrap-around from 359° → 1° is
  /// handled correctly.
  double _smooth(double newDeg) {
    final old = _lastHeadingDeg;
    if (old == null) return newDeg;
    var diff = newDeg - old;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    var result = old + smoothing * diff;
    if (result < 0) result += 360;
    if (result >= 360) result -= 360;
    return result;
  }
}

/// Returns the shortest signed angular difference `(a - b)` in degrees,
/// normalised to `[-180, 180]`.
double angularDifferenceDeg(double a, double b) {
  var d = (a - b) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Picks a bearing that blends a phone-compass reading with a GPS course.
///
/// - Below `minTrustSpeedMps` (e.g. standing still) GPS course is unreliable,
///   so the compass wins.
/// - Above `fullTrustSpeedMps` (e.g. cycling/driving) the GPS course is the
///   ground truth and the compass — which only knows where the phone is
///   pointed — is ignored.
/// - In between we interpolate so the camera doesn't snap.
///
/// Either input may be null; the other is returned. If both are null the
/// function returns null.
double? fusedBearingDeg({
  required double? compassDeg,
  required double? gpsCourseDeg,
  required double speedMps,
  double minTrustSpeedMps = 1.0,
  double fullTrustSpeedMps = 4.0,
}) {
  if (compassDeg == null) return gpsCourseDeg;
  if (gpsCourseDeg == null) return compassDeg;
  final span = (fullTrustSpeedMps - minTrustSpeedMps).abs();
  final gpsWeight = span == 0
      ? (speedMps >= fullTrustSpeedMps ? 1.0 : 0.0)
      : ((speedMps - minTrustSpeedMps) / span).clamp(0.0, 1.0);
  if (gpsWeight <= 0) return compassDeg;
  if (gpsWeight >= 1) return gpsCourseDeg;
  // Interpolate along the shorter arc.
  final diff = angularDifferenceDeg(gpsCourseDeg, compassDeg);
  var result = compassDeg + gpsWeight * diff;
  if (result < 0) result += 360;
  if (result >= 360) result -= 360;
  return result;
}
