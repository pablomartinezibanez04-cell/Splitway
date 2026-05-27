import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Immutable snapshot of app + device identity, captured once at startup
/// and attached to every [LogEntry].
class DeviceMetadata {
  const DeviceMetadata({
    required this.appVersion,
    required this.platform,
    required this.deviceModel,
  });

  final String appVersion;
  final String platform;
  final String deviceModel;

  /// Returns a metadata snapshot, swallowing any plugin failure into safe
  /// fallback strings so logging never breaks because of metadata.
  static Future<DeviceMetadata> capture({
    PackageInfo? packageInfoOverride,
    DeviceInfoPlugin? deviceInfoOverride,
  }) async {
    String appVersion = 'unknown';
    String platform = 'unknown';
    String deviceModel = 'unknown';

    try {
      final pkg = packageInfoOverride ?? await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}

    try {
      final info = deviceInfoOverride ?? DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        platform = 'android ${a.version.release}';
        deviceModel = '${a.manufacturer} ${a.model}'.trim();
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        platform = 'ios ${i.systemVersion}';
        deviceModel = i.utsname.machine;
      } else if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        platform = 'macos ${m.osRelease}';
        deviceModel = m.model;
      } else if (Platform.isWindows) {
        final w = await info.windowsInfo;
        platform = 'windows ${w.majorVersion}.${w.minorVersion}';
        deviceModel = w.computerName;
      } else if (Platform.isLinux) {
        final l = await info.linuxInfo;
        platform = 'linux ${l.versionId ?? ''}'.trim();
        deviceModel = l.prettyName;
      }
    } catch (_) {}

    return DeviceMetadata(
      appVersion: appVersion,
      platform: platform,
      deviceModel: deviceModel,
    );
  }
}
