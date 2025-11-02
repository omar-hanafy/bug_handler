import 'package:bug_reporting_system/context/provider.dart';
import 'package:bug_reporting_system/core/event.dart';
import 'package:bug_reporting_system/privacy/sanitizers.dart';
import 'package:bug_reporting_system/reporters/composite_reporter.dart';
import 'package:bug_reporting_system/reporters/reporter.dart';

/// System severity levels used across exceptions and policies.
enum Severity {
  /// Fatal user-facing outage or data-loss scenario.
  critical,

  /// Recoverable error that still requires immediate attention.
  error,

  /// Degraded experience or policy violation that may be ignored automatically.
  warning,

  /// Informational signal useful for debugging or telemetry only.
  info,
}

/// Backwards compatible alias for older code that referenced ErrorSeverity.
typedef ErrorSeverity = Severity;

/// Rate limit policy (windowed).
class RateLimit {
  /// Creates a rate limit that permits [maxEvents] per [per] duration window.
  const RateLimit(this.maxEvents, this.per);

  /// Maximum number of events allowed within the window.
  final int maxEvents;

  /// Duration that bounds the rate-limit window.
  final Duration per;
}

/// Dedupe policy (time-windowed, fingerprint-based).
class DedupeStrategy {
  /// Creates a dedupe strategy that treats events as duplicates within [window].
  const DedupeStrategy.windowed([this.window = const Duration(seconds: 60)]);

  /// The period during which events with the same fingerprint are dropped.
  final Duration window;
}

/// Policy determines if a given event qualifies for sending, based on:
/// - severity threshold
/// - environment gates
/// - whether handled exceptions should be reported (vs only uncaught)
/// Sampling, rate-limit, and dedupe are enforced at runtime (client) level.
class Policy {
  /// Creates a policy with optional overrides for gating behavior.
  const Policy({
    this.minSeverity = Severity.error,
    this.reportHandled = true,
    this.environments = const {},
    this.sampling = 1.0,
    this.rateLimit = const RateLimit(10, Duration(minutes: 1)),
    this.dedupe = const DedupeStrategy.windowed(),
  });

  /// Minimum severity that must be met for an event to qualify.
  final Severity minSeverity;

  /// Whether handled (caught) exceptions should be reported automatically.
  final bool reportHandled;

  /// Allowed environments; empty set means "any".
  final Set<String> environments; // if empty => allow all

  /// Sampling probability (0..1) applied before runtime gating.

  final double sampling; // 0..1

  /// Rate-limiting configuration applied at runtime.
  final RateLimit rateLimit;

  /// Dedupe strategy applied at runtime.
  final DedupeStrategy dedupe;

  /// Basic gating performed before runtime controls (sampling, rate-limit, dedupe).
  bool shouldSend(ReportEvent event, String currentEnvironment) {
    // Environment gate
    if (environments.isNotEmpty && !environments.contains(currentEnvironment)) {
      return false;
    }

    // Severity gate
    if (event.exception.severity.index > minSeverity.index) {
      return false;
    }

    // Handled/unhandled gate
    if (!reportHandled && event.handled) {
      return false;
    }

    return true;
  }
}

/// Event transformation hook (e.g., tag rewriting, message normalization).
typedef EventTransform = ReportEvent Function(ReportEvent e);

/// Client configuration for the bug reporting system.
class ClientConfig {
  /// Aggregates configuration for the bug reporting pipeline.
  const ClientConfig({
    required this.environment,
    this.baseProviders = const [],
    this.additionalProviders = const [],
    this.sanitizers = const [],
    this.transforms = const [],
    this.policy = const Policy(),
    this.reporters = const [],
    this.maxBreadcrumbs = 100,
  });

  /// Logical environment label (e.g., "dev", "staging", "prod").
  final String environment;

  /// Always-on providers (should be lightweight).
  final List<ContextProvider> baseProviders;

  /// Additional providers (often user/session/network); may include manual-only ones.
  final List<ContextProvider> additionalProviders;

  /// Sanitizers applied to the serialized event map before delivery/outbox.
  final List<Sanitizer> sanitizers;

  /// Event transforms applied before sanitization.
  final List<EventTransform> transforms;

  /// Reporting policy configuration.
  final Policy policy;

  /// Reporter pipeline (fan-out via CompositeReporter).
  final List<Reporter> reporters;

  /// Max breadcrumbs to keep in memory (ring buffer).
  final int maxBreadcrumbs;

  /// Builds the fan-out pipeline (CompositeReporter).
  Reporter buildPipeline() => CompositeReporter(reporters);

  /// Applies transforms in order, returning the transformed event.
  ReportEvent applyTransforms(ReportEvent event) {
    var out = event;
    for (final t in transforms) {
      out = t(out);
    }
    return out;
  }

  /// Produces a fully sanitized payload map from an event.
  Map<String, dynamic> sanitize(ReportEvent event) {
    var map = event.toMap(); // raw, unsanitized
    for (final s in sanitizers) {
      map = s.sanitize(map);
    }
    return map;
  }
}
