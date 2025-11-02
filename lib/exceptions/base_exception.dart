import 'dart:collection';

import 'package:bug_reporting_system/core/config.dart' show Severity;
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Base class all domain exceptions should extend.
///
/// - Immutable: all fields are final and metadata is wrapped in an
///   unmodifiable view to prevent mutation.
/// - Comparable: implements Equatable for consistent comparisons in tests/state.
/// - Severity-aware: integrates with the reporting policy via [severity].
@immutable
abstract class BaseException extends Equatable implements Exception {
  /// Creates a base exception with immutable metadata and derived stack trace.
  BaseException({
    required this.userMessage,
    required this.devMessage,
    this.cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
    this.severity = Severity.error,
    this.isReportable = true,
  })  : stack = stack ?? StackTrace.current,
        metadata = UnmodifiableMapView(Map<String, dynamic>.from(metadata));

  /// Human-friendly text appropriate for end-users.
  final String userMessage;

  /// Developer-friendly details, safe for logs and tools.
  final String devMessage;

  /// Original underlying error, if any.
  final Object? cause;

  /// Capture location. Defaults to [StackTrace.current] when not provided.
  final StackTrace? stack;

  /// Additional diagnostic data related to this exception.
  final Map<String, dynamic> metadata;

  /// How serious this exception is.
  final Severity severity;

  /// Whether this exception should be reported automatically.
  final bool isReportable;

  @override
  List<Object?> get props => <Object?>[
        runtimeType,
        userMessage,
        devMessage,
        severity,
        isReportable,
        metadata,
        cause.runtimeType,
        // NOTE: stack is intentionally excluded to avoid noisy equality.
      ];

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('$runtimeType')
      ..writeln('  userMessage: $userMessage')
      ..writeln('  devMessage : $devMessage')
      ..writeln('  severity   : $severity')
      ..writeln('  reportable : $isReportable');
    if (metadata.isNotEmpty) {
      buf.writeln('  metadata   : $metadata');
    }
    if (cause != null) {
      buf.writeln('  cause      : ${cause.runtimeType}: $cause');
    }
    if (stack != null) {
      buf.writeln('  stack      :\n$stack');
    }
    return buf.toString().trimRight();
  }
}
