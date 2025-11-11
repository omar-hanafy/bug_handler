import 'package:bug_handler/context/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Provides device/OS/runtime information. Data is intentionally scoped to what
/// is helpful for diagnostics and safe for privacy by default.
class DeviceContextProvider extends ContextProvider with CachedContextProvider {
  /// Creates a device context provider, allowing dependency injection for
  /// testing by supplying a custom [DeviceInfoPlugin] instance.
  DeviceContextProvider({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  @override
  String get name => 'device';

  @override
  Duration get cacheDuration => const Duration(hours: 1);

  @override
  Future<Map<String, dynamic>> collect() async {
    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        return {
          'platform': 'web',
          'browserName': info.browserName.name,
          'appVersion': info.appVersion,
          'platformVersion': info.platform,
          'userAgent': info.userAgent,
          'hardwareConcurrency': info.hardwareConcurrency,
          'language': info.language,
          'languages': info.languages,
          'vendor': info.vendor,
          'vendorSub': info.vendorSub,
          'product': info.product,
          'productSub': info.productSub,
          'maxTouchPoints': info.maxTouchPoints,
          'deviceMemoryGb': info.deviceMemory,
        };
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final a = await _deviceInfo.androidInfo;
          return {
            'platform': 'android',
            'brand': a.brand,
            'manufacturer': a.manufacturer,
            'model': a.model,
            'device': a.device,
            'product': a.product,
            'hardware': a.hardware,
            'isPhysicalDevice': a.isPhysicalDevice,
            'id': a.id,
            'board': a.board,
            'bootloader': a.bootloader,
            'display': a.display,
            'fingerprint': a.fingerprint,
            'tags': a.tags,
            'type': a.type,
            'version': {
              'release': a.version.release,
              'sdkInt': a.version.sdkInt,
              'codename': a.version.codename,
              'baseOS': a.version.baseOS,
              'incremental': a.version.incremental,
              'securityPatch': a.version.securityPatch,
              'previewSdkInt': a.version.previewSdkInt,
            },
          };
        case TargetPlatform.iOS:
          final i = await _deviceInfo.iosInfo;
          return {
            'platform': 'ios',
            'name': i.name,
            'systemName': i.systemName,
            'systemVersion': i.systemVersion,
            'model': i.model,
            'localizedModel': i.localizedModel,
            'identifierForVendor': '${i.identifierForVendor}',
            'isPhysicalDevice': i.isPhysicalDevice,
            'utsname': {
              'sysname': i.utsname.sysname,
              'nodename': i.utsname.nodename,
              'release': i.utsname.release,
              'version': i.utsname.version,
              'machine': i.utsname.machine,
            },
          };
        case TargetPlatform.macOS:
          final m = await _deviceInfo.macOsInfo;
          return {
            'platform': 'macos',
            'computerName': m.computerName,
            'model': m.model,
            'kernelVersion': m.kernelVersion,
            'osRelease': m.osRelease,
            'arch': m.arch,
            'activeCPUs': m.activeCPUs,
            'memorySize': m.memorySize,
            'hostName': m.hostName,
            'systemGUID': m.systemGUID,
            'majorVersion': m.majorVersion,
            'minorVersion': m.minorVersion,
            'patchVersion': m.patchVersion,
          };
        case TargetPlatform.windows:
          final w = await _deviceInfo.windowsInfo;
          return {
            'platform': 'windows',
            'computerName': w.computerName,
            'numberOfCores': w.numberOfCores,
            'systemMemoryInMegabytes': w.systemMemoryInMegabytes,
            'userName': w.userName,
            'buildLab': w.buildLab,
            'buildLabEx': w.buildLabEx,
            'displayVersion': w.displayVersion,
            'productName': w.productName,
            'releaseId': w.releaseId,
            'majorVersion': w.majorVersion,
            'minorVersion': w.minorVersion,
            'buildNumber': w.buildNumber,
          };
        case TargetPlatform.linux:
          final l = await _deviceInfo.linuxInfo;
          return {
            'platform': 'linux',
            'name': l.name,
            'version': l.version,
            'id': l.id,
            'idLike': l.idLike,
            'versionCodename': l.versionCodename,
            'versionId': l.versionId,
            'prettyName': l.prettyName,
            'variant': l.variant,
            'variantId': l.variantId,
            'machineId': l.machineId,
          };
        case TargetPlatform.fuchsia:
          final f = await _deviceInfo.deviceInfo;
          return {
            'platform': 'fuchsia',
            'data': f.data,
          };
      }
    } catch (_) {
      // Provide a minimal, safe fallback.
      return <String, dynamic>{
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      };
    }
  }
}
