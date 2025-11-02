import 'dart:async';

import 'package:meta/meta.dart';

/// Base contract for providing structured diagnostic context that can be
/// attached to error/report events.
///
/// Providers should be:
/// - Fast and resilient (never throw out of [getData]).
/// - Conscious about privacy (avoid PII by default).
/// - Lightweight by default; heavy data should be opt‑in or manual‑only.
@immutable
abstract class ContextProvider {
  /// Allows subclasses to be `const` and satisfy immutability lint rules.
  const ContextProvider();

  /// The key under which this provider's map is attached to the report context.
  String get name;

  /// If true, this context is collected only for **manual** user‑initiated reports
  /// (e.g., when the user taps "Send diagnostics"), and **not** for automatic
  /// background reporting.
  bool get manualReportOnly => false;

  /// Collects context data. Implementations must never throw; if an internal
  /// error occurs, return an empty map instead.
  FutureOr<Map<String, dynamic>> getData();

  /// Optional validation; return `true` to keep the data in the report.
  /// The default keeps any non‑empty map.
  bool validateData(Map<String, dynamic> data) => data.isNotEmpty;
}

/// A simple wrapper that keeps a mutable [value] while allowing the field
/// that holds the wrapper to remain `final`, satisfying `@immutable` lints.
class _Cell<T> {
  _Cell(this.value);

  T value;
}

/// A caching mixin that ensures:
/// - Throttled collection (via [cacheDuration])
/// - In‑flight deduplication (concurrent callers share one collection Future)
/// - Resilience (errors return `{}` and do not break the pipeline)
///
/// The internal state is stored inside final wrapper cells to comply with
/// `@immutable` (fields themselves are final; only the inner values change).
mixin CachedContextProvider on ContextProvider {
  // Final cells to satisfy immutability lints.
  final _Cell<Map<String, dynamic>?> _cacheCell =
      _Cell<Map<String, dynamic>?>(null);
  final _Cell<DateTime?> _timestampCell = _Cell<DateTime?>(null);
  final _Cell<Future<Map<String, dynamic>>?> _inFlightCell =
      _Cell<Future<Map<String, dynamic>>?>(null);

  /// Cache TTL for this provider. Keep short for dynamic data, longer for static.
  Duration get cacheDuration => const Duration(minutes: 5);

  bool get _cacheValid {
    final ts = _timestampCell.value;
    return _cacheCell.value != null &&
        ts != null &&
        DateTime.now().difference(ts) < cacheDuration;
  }

  /// Override this instead of [getData] to implement the actual data collection.
  @protected
  FutureOr<Map<String, dynamic>> collect();

  /// Clears the cached value, forcing the next call to hit [collect].
  void clearCache() {
    _cacheCell.value = null;
    _timestampCell.value = null;
  }

  @override
  Future<Map<String, dynamic>> getData() {
    if (_cacheValid) {
      // Non-null by contract when _cacheValid is true.
      return Future.value(_cacheCell.value!);
    }

    final inFlight = _inFlightCell.value;
    if (inFlight != null) return inFlight;

    final future = _safeCollect();
    _inFlightCell.value = future;
    return future.whenComplete(() => _inFlightCell.value = null);
  }

  Future<Map<String, dynamic>> _safeCollect() async {
    try {
      final result = await Future<Map<String, dynamic>>.value(collect());
      if (validateData(result)) {
        _cacheCell.value = result;
        _timestampCell.value = DateTime.now();
      }
      // If invalid, still return what we got (callers can inspect or ignore).
      return result;
    } catch (_) {
      // Never throw from providers. Return empty map to keep the pipeline healthy.
      return <String, dynamic>{};
    }
  }
}
