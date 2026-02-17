import 'package:bug_handler/context/built_in/device_context.dart';
import 'package:bug_handler/context/provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_helper_utils/flutter_helper_utils.dart';

/// Provides device-specific information for error reports
/// Only collects essential info needed for debugging/reproduction
class DeviceContextProvider extends ContextProvider with CachedContextProvider {
  DeviceContextProvider({
    DeviceInfoPlugin? deviceInfo,
    super.additionalData,
  }) : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  @override
  String get name => 'device';

  @override
  Future<Map<String, dynamic>> collectData() async {
    return {
      ...await _collectData(),
      if (additionalData != null) ...additionalData!.call(),
    };
  }

  Future<Map<String, dynamic>> _collectData() async {
    try {
      if (PlatformEnv.isIOS) {
        return (await _deviceInfo.iosInfo).report;
      } else if (PlatformEnv.isAndroid) {
        return (await _deviceInfo.androidInfo).report;
      }
      return (await _deviceInfo.deviceInfo).data;
    } catch (_) {
      return PlatformEnv.report();
    }
  }
}

extension IosDeviceInfoEx on IosDeviceInfo {
  Map<String, Object?> get report => {
    'dart_platform': PlatformEnv.report(),
    'name': name,
    'systemName': systemName,
    'systemVersion': systemVersion,
    'model': model,
    'localizedModel': localizedModel,
    'identifierForVendor': '$identifierForVendor',
    'isPhysicalDevice': '$isPhysicalDevice',
    'utsname': {
      'sysname': utsname.sysname,
      'nodename': utsname.nodename,
      'release': utsname.release,
      'version': utsname.version,
      'machine': utsname.machine,
    },
  };
}

extension AndroidDeviceInfoEx on AndroidDeviceInfo {
  Map<String, Object?> get report => {
    'dart_platform': PlatformEnv.report(),
    'board': board,
    'bootloader': bootloader,
    'brand': brand,
    'device': device,
    'display': display,
    'fingerprint': fingerprint,
    'hardware': hardware,
    'host': host,
    'id': id,
    'manufacturer': manufacturer,
    'model': model,
    'product': product,
    'tags': tags,
    'type': type,
    'isPhysicalDevice': '$isPhysicalDevice',
    'isLowRamDevice': '$isLowRamDevice',
    'version': {
      'baseOS': '${version.baseOS}',
      'codename': version.codename,
      'incremental': version.incremental,
      'previewSdkInt': '${version.previewSdkInt}',
      'release': version.release,
      'sdkInt': '${version.sdkInt}',
      'securityPatch': '${version.securityPatch}',
    },
  };
}
