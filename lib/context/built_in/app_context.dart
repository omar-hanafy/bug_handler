import 'dart:developer';

import 'package:battery_plus/battery_plus.dart';
import 'package:bug_handler/context/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Provides comprehensive application and device information for error reports
class AppContextProvider extends ContextProvider with CachedContextProvider {
  AppContextProvider({
    PackageInfo? packageInfo,
    super.additionalData,
  }) : _packageInfo = packageInfo;

  final PackageInfo? _packageInfo;

  @override
  String get name => 'app';

  @override
  Future<Map<String, dynamic>> collectData() async {
    try {
      final packageInfo = _packageInfo ?? await PackageInfo.fromPlatform();

      return {
        // App information
        'appName': packageInfo.appName,
        'packageName': packageInfo.packageName,
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
        'buildSignature': packageInfo.buildSignature,

        // Network status
        'networkStatus': await _getNetworkStatus(),

        // Battery level
        'deviceBattery': await _getBatteryLevel(),

        // Include any additional data provided
        if (additionalData != null) ...additionalData!.call(),
      };
    } catch (e, s) {
      log('Error collecting app context data', error: e, stackTrace: s);
      // Fallback to basic info if any part fails
      return {
        'appName': 'Unknown',
        'version': 'Unknown',
        if (additionalData != null) ...additionalData!.call(),
      };
    }
  }

  Future<List<String>> _getNetworkStatus() async {
    final results = await Connectivity().checkConnectivity();
    return results.map((e) => e.name).toList();
  }

  Future<int> _getBatteryLevel() async {
    try {
      return await Battery().batteryLevel;
    } catch (e, s) {
      log(
        'Could not get battery level in the report!',
        error: e,
        stackTrace: s,
      );
    }
    return -1;
  }
}
