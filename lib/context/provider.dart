import 'dart:async';

import 'package:meta/meta.dart';

/// Base class for context providers that collect data for error reports
abstract class ContextProvider {
  const ContextProvider({this.additionalData});

  /// Name of this context provider
  /// Used as the key in the report context map
  String get name;

  final Map<String, dynamic> Function()? additionalData;

  /// Whether this context should only be included in manual reports
  /// Useful for heavier contexts that aren't needed for automatic reporting
  bool get manualReportOnly => false;

  /// Collect the context data
  /// Returns a map of data that will be included in reports
  /// Should handle errors gracefully and return empty map on failure
  FutureOr<Map<String, dynamic>> getData();

  /// Optional validation of the collected data
  /// Return true if the data is valid and should be included
  bool validateData(Map<String, dynamic> data) => data.isNotEmpty;
}

/// Mixin for providers that cache their data
mixin CachedContextProvider on ContextProvider {
  Map<String, dynamic>? _cachedData;
  DateTime? _lastUpdate;

  /// How long the cached data should be considered valid
  Duration get cacheDuration => const Duration(minutes: 5);

  /// Whether the cached data is still valid
  bool get isCacheValid =>
      _cachedData != null &&
      _lastUpdate != null &&
      DateTime.now().difference(_lastUpdate!) < cacheDuration;

  /// Get data with caching
  @override
  Future<Map<String, dynamic>> getData() async {
    if (isCacheValid) return _cachedData!;

    final data = await collectData();
    if (validateData(data)) {
      _cachedData = data;
      _lastUpdate = DateTime.now();
    }
    return data;
  }

  /// Implement this instead of getData when using cache
  @protected
  FutureOr<Map<String, dynamic>> collectData();

  /// Clear the cached data
  void clearCache() {
    _cachedData = null;
    _lastUpdate = null;
  }
}
