import 'package:splitway_core/splitway_core.dart';

/// The run time to compare against a route's "normal time": the best completed
/// lap on a closed circuit, or the whole-session duration on an open route.
/// Returns null when no comparable time exists.
Duration? representativeRunTime(RouteTemplate route, SessionRun session) {
  if (route.isClosed) return session.bestLap?.duration;
  return session.totalDuration;
}

/// Signed percentage of [actual] vs [expected]: negative = faster (time saved),
/// positive = slower (time lost). Null when [expected] is non-positive.
double? runDeltaPercent({
  required Duration expected,
  required Duration actual,
}) {
  final e = expected.inMilliseconds;
  if (e <= 0) return null;
  final a = actual.inMilliseconds;
  return (a - e) / e * 100.0;
}
