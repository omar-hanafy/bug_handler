import 'package:battery_plus/battery_plus.dart';
import 'package:bug_handler/context/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Provides application/package metadata + lightweight runtime signals that are
/// safe to collect automatically (network summary, battery level).
///
/// Avoids UI/BuildContext to keep it usable at app startup and in isolates.
class AppContextProvider extends ContextProvider with CachedContextProvider {
  /// Creates an app context provider with optional injected dependencies and
  /// a hook for attaching additional custom metadata.
  AppContextProvider({
    PackageInfo? packageInfo,
    Battery? battery,
    Connectivity? connectivity,
    Map<String, dynamic> Function()? additional,
  })  : _packageInfo = packageInfo,
        _battery = battery ?? Battery(),
        _connectivity = connectivity ?? Connectivity(),
        _additional = additional;

  final PackageInfo? _packageInfo;
  final Battery _battery;
  final Connectivity _connectivity;
  final Map<String, dynamic> Function()? _additional;

  @override
  String get name => 'app';

  @override
  Duration get cacheDuration => const Duration(minutes: 2);

  @override
  Future<Map<String, dynamic>> collect() async {
    final pkg = _packageInfo ?? await PackageInfo.fromPlatform();

    // Connectivity may return multiple active interfaces on some platforms.
    final interfaces = await _interfaces();

    // Battery level may throw on some platforms; handled in _batteryLevel().
    final batteryLevel = await _batteryLevel();

    return <String, dynamic>{
      'appName': pkg.appName,
      'packageName': pkg.packageName,
      'version': pkg.version,
      'buildNumber': pkg.buildNumber,
      'buildSignature': pkg.buildSignature,
      'installerStore': pkg.installerStore,
      'network': {
        'interfaces': interfaces,
      },
      'battery': {
        'level': batteryLevel,
      },
      if (_additional != null) ..._additional(),
    };
  }

  Future<List<String>> _interfaces() async {
    try {
      // connectivity_plus always returns a list of results, even if it's empty
      // or contains a single element (e.g., [ConnectivityResult.wifi]).
      final results = await _connectivity.checkConnectivity();

      // We can now directly map the list, as the old check is no longer needed.
      return results.map((e) => e.name).toList(growable: false);
    } catch (_) {
      // Return an empty list on any error
      return const <String>[];
    }
  }

  Future<int> _batteryLevel() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return -1; // Unknown
    }
  }
}
