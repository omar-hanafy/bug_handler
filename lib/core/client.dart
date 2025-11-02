import 'dart:async';
import 'dart:math';

import 'package:bug_reporting_system/context/provider.dart';
import 'package:bug_reporting_system/core/config.dart';
import 'package:bug_reporting_system/core/event.dart';
import 'package:bug_reporting_system/core/outbox.dart';
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:bug_reporting_system/reporters/reporter.dart';

/// Central orchestrator for the bug reporting system (v2).
/// - Initializes configuration and reporter pipeline
/// - Collects context (built-in + app-provided)
/// - Applies transforms and sanitizers
/// - Enforces policy (severity, sampling, dedupe, rate-limit)
/// - Persists to a durable outbox when delivery fails
class BugReportClient {
  BugReportClient._();

  /// Global singleton used across the app to coordinate reporting.
  static final BugReportClient instance = BugReportClient._();

  ClientConfig? _config;
  Reporter? _pipeline;

  final Outbox _outbox = Outbox();
  final List<ContextProvider> _dynamicProviders = <ContextProvider>[];

  // In-memory breadcrumbs ring buffer
  final List<Breadcrumb> _breadcrumbs = <Breadcrumb>[];
  int _maxBreadcrumbs = 100;

  // Policy runtime helpers
  late _RateLimiter _rateLimiter;
  late _DedupeIndex _dedupeIndex;
  final Random _rng = Random();

  /// Indicates whether [initialize] has been called.
  bool get isInitialized => _config != null;

  /// Initialize the client with the given [config].
  /// This must be called once during application bootstrap.
  Future<void> initialize(ClientConfig config) async {
    if (isInitialized) return;

    _config = config;
    _pipeline = config.buildPipeline();

    _maxBreadcrumbs = config.maxBreadcrumbs;
    _rateLimiter = _RateLimiter(
        config.policy.rateLimit.maxEvents, config.policy.rateLimit.per);
    _dedupeIndex = _DedupeIndex(config.policy.dedupe.window);

    // Optionally: preload light base contexts (let providers decide).
    // Do not run heavy providers here; collection is done per-event.
  }

  /// Adds a runtime context provider (e.g., current user/session).
  /// This supplements [ClientConfig.additionalProviders].
  void addContextProvider(ContextProvider provider) {
    if (_dynamicProviders.contains(provider)) return;
    _dynamicProviders.add(provider);
  }

  /// Removes a previously added runtime context provider.
  void removeContextProvider(ContextProvider provider) {
    _dynamicProviders.remove(provider);
  }

  /// Clears all runtime context providers.
  void clearContextProviders() {
    _dynamicProviders.clear();
  }

  /// Adds a breadcrumb to the ring buffer, keeping only the most recent [_maxBreadcrumbs].
  void addBreadcrumb(
    String message, {
    Map<String, dynamic> data = const {},
    DateTime? timestamp,
  }) {
    _breadcrumbs.add(
      Breadcrumb(
          timestamp: timestamp ?? DateTime.now(), message: message, data: data),
    );
    if (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeRange(0, _breadcrumbs.length - _maxBreadcrumbs);
    }
  }

  /// Clears all breadcrumbs currently buffered.
  void clearBreadcrumbs() {
    _breadcrumbs.clear();
  }

  /// Creates a [ReportEvent] from a [BaseException], collecting and merging contexts,
  /// applying transforms and sanitizers, and returning a **sanitized** event ready for delivery.
  ///
  /// If [manual] is true, manual-only context providers are included.
  Future<ReportEvent> createEvent(
    BaseException exception, {
    Map<String, dynamic> additionalContext = const {},
    bool manual = false,
    bool handled = true,
  }) async {
    final cfg = _ensureConfig();

    final baseCtx = await _collectContext(
      base: cfg.baseProviders,
      additional: [
        ...cfg.additionalProviders,
        ..._dynamicProviders,
      ],
      includeManualOnly: manual,
    );

    final rawEvent = ReportEvent(
      id: ReportEvent.generateId(),
      exception: exception,
      context: {
        'environment': cfg.environment,
        'handled': handled,
        ...baseCtx,
        if (additionalContext.isNotEmpty) ...additionalContext,
      },
      timestamp: DateTime.now(),
      breadcrumbs: List.unmodifiable(_breadcrumbs),
      fingerprints: _computeFingerprints(exception),
      handled: handled,
    );

    // Apply transforms (e.g., tagging, rewriting) then sanitizers to produce a safe payload.
    final transformed = cfg.applyTransforms(rawEvent);
    final sanitizedPayload = cfg.sanitize(transformed);

    // Embed the sanitized payload for downstream reporters and outbox persistence.
    return transformed.withPayload(sanitizedPayload);
  }

  /// Reports (delivers) a pre-built [ReportEvent] via the configured pipeline, respecting policy.
  /// Returns `true` if at least one reporter successfully delivered the event.
  ///
  /// On delivery failure or when rate-limited, the event is persisted to the outbox.
  Future<bool> report(ReportEvent event) async {
    final cfg = _ensureConfig();

    // Basic policy gate: severity threshold and handled/unhandled allowance.
    if (!cfg.policy.shouldSend(event, cfg.environment)) {
      return false;
    }

    // Sampling (0..1). If sampling < 1.0, probabilistically drop.
    if (cfg.policy.sampling < 1.0 && _rng.nextDouble() > cfg.policy.sampling) {
      return false;
    }

    // Dedupe: drop events with the same primary fingerprint within the dedupe window.
    final primaryFingerprint = _primaryFingerprintOf(event);
    if (primaryFingerprint != null &&
        _dedupeIndex.isDuplicate(primaryFingerprint)) {
      return false;
    }

    // Rate-limit: if the window is saturated, persist to outbox for later.
    if (!_rateLimiter.allow()) {
      await _outbox.enqueue(event);
      return false;
    }

    // Attempt delivery.
    final ok = await _pipeline!.send(event);
    if (!ok) {
      await _outbox.enqueue(event);
    }
    return ok;
  }

  /// Convenience method to capture and report an exception directly.
  Future<ReportEvent> capture(
    BaseException exception, {
    Map<String, dynamic> additionalContext = const {},
    bool manual = false,
    bool handled = true,
  }) async {
    final event = await createEvent(
      exception,
      additionalContext: additionalContext,
      manual: manual,
      handled: handled,
    );
    await report(event);
    return event;
  }

  /// Flushes any events persisted in the outbox.
  Future<void> flush() async {
    _ensureConfig();
    await _outbox.flushWith(_pipeline!);
  }

  // ---- internals ----

  ClientConfig _ensureConfig() {
    final cfg = _config;
    if (cfg == null) {
      throw StateError(
          'BugReportClient is not initialized. Call initialize() first.');
    }
    return cfg;
  }

  Future<Map<String, dynamic>> _collectContext({
    required List<ContextProvider> base,
    required List<ContextProvider> additional,
    required bool includeManualOnly,
  }) async {
    final result = <String, dynamic>{};

    Future<void> run(ContextProvider p) async {
      try {
        if (!includeManualOnly && p.manualReportOnly) return;
        final data = await p.getData();
        if (p.validateData(data)) {
          result[p.name] = data;
        }
      } catch (_) {
        // Providers must be resilient; ignore failures, do not block reporting.
      }
    }

    for (final p in base) {
      await run(p);
    }
    for (final p in additional) {
      await run(p);
    }
    return result;
  }

  List<String> _computeFingerprints(BaseException e) {
    final type = e.runtimeType.toString();
    final dev = e.devMessage;
    final src = e.metadata['source']?.toString();
    final topFrame = _topStackFrame(e.stack);

    return <String>[
      type,
      if (src != null && src.isNotEmpty) 'src:$src',
      if (topFrame != null) 'frame:$topFrame',
      'msg:${_hash(dev)}',
    ];
  }

  String? _primaryFingerprintOf(ReportEvent e) {
    if (e.fingerprints.isEmpty) return null;
    // You can choose any deterministic primary; here we use the first.
    return e.fingerprints.first;
  }

  String? _topStackFrame(StackTrace? s) {
    if (s == null) return null;
    final lines = s.toString().split('\n');
    if (lines.isEmpty) return null;
    final first = lines.first.trim();
    return first.isEmpty ? null : first;
  }

  // Simple non-cryptographic hash.
  String _hash(String input) {
    var h = 1125899906842597; // large prime
    for (var i = 0; i < input.length; i++) {
      h = (h * 1315423911) ^ input.codeUnitAt(i);
    }
    return h.toUnsigned(64).toRadixString(16);
  }
}

// ---- Policy runtime helpers ----

class _RateLimiter {
  _RateLimiter(this._max, this._per);

  final int _max;
  final Duration _per;

  int _count = 0;
  DateTime _windowStart = DateTime.fromMillisecondsSinceEpoch(0);

  bool allow() {
    final now = DateTime.now();
    if (now.difference(_windowStart) > _per) {
      _windowStart = now;
      _count = 0;
    }
    if (_count >= _max) return false;
    _count++;
    return true;
  }
}

class _DedupeIndex {
  _DedupeIndex(this._window);

  final Duration _window;
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  bool isDuplicate(String key) {
    final now = DateTime.now();
    _cleanup(now);
    final last = _lastSeen[key];
    final dup = last != null && now.difference(last) <= _window;
    _lastSeen[key] = now;
    return dup;
  }

  void _cleanup(DateTime now) {
    if (_lastSeen.length < 512) return;
    final cutoff = now.subtract(_window);
    _lastSeen.removeWhere((_, ts) => ts.isBefore(cutoff));
  }
}
