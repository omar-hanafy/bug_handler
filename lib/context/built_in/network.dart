import 'package:bug_reporting_system/context/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// Connectivity & transport snapshot. Provides a normalized view of active
/// interfaces and, when available and allowed by platform permissions, basic
/// Wi‑Fi details (SSID/BSSID/IPs). Values may be `null` when not accessible.
class NetworkContextProvider extends ContextProvider
    with CachedContextProvider {
  /// Creates a network context provider with injectable connectivity and network
  /// info dependencies for easier testing.
  NetworkContextProvider({
    Connectivity? connectivity,
    NetworkInfo? info,
  })  : _connectivity = connectivity ?? Connectivity(),
        _info = info ?? NetworkInfo();

  final Connectivity _connectivity;
  final NetworkInfo _info;

  @override
  String get name => 'network';

  @override
  Duration get cacheDuration => const Duration(minutes: 1);

  @override
  Future<Map<String, dynamic>> collect() async {
    final interfaces = await _interfaces();

    // Only attempt Wi‑Fi details if Wi‑Fi is among the active interfaces.
    final hasWifi = interfaces.contains('wifi');

    final wifi = hasWifi ? await _wifiDetails() : const <String, dynamic>{};

    return <String, dynamic>{
      'interfaces': interfaces,
      if (wifi.isNotEmpty) 'wifi': wifi,
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

  Future<Map<String, dynamic>> _wifiDetails() async {
    try {
      final ssid = await _info.getWifiName(); // may require permissions
      final bssid = await _info.getWifiBSSID();
      final ipv4 = await _info.getWifiIP();
      final ipv6 = await _info.getWifiIPv6();

      return <String, dynamic>{
        if (ssid != null && ssid.isNotEmpty) 'ssid': ssid,
        if (bssid != null && bssid.isNotEmpty) 'bssid': bssid,
        if (ipv4 != null && ipv4.isNotEmpty) 'ipv4': ipv4,
        if (ipv6 != null && ipv6.isNotEmpty) 'ipv6': ipv6,
      };
    } catch (_) {
      // Silent failure; details unavailable on this platform or permission denied.
      return const <String, dynamic>{};
    }
  }
}
