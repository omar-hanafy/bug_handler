import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/context/provider.dart';
import 'package:bug_handler/core/report.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Callback that's triggered before sending a report
/// Return false to cancel the send operation
typedef PreSendReportCallback = Future<bool> Function(Report report);

/// Callback that's triggered before sharing a report
/// Return false to cancel the share operation
typedef PreShareReportCallback = Future<bool> Function(Report report);

@immutable
class ReportConfig {
  ReportConfig({
    this.sentryDsn,
    required this.environments,
    required this.currentEnvironment,
    this.baseProviders = const [],
    this.minSeverity = ErrorSeverity.error,
    this.enableSentry,
    this.onPreSendReport,
    this.onPreShareReport,
  }) : assert(
         environments.contains(currentEnvironment),
         'Current environment must be one of the provided environments',
       );

  /// Sentry DSN for error reporting
  /// If null, Sentry reporting will be disabled
  final String? sentryDsn;

  /// List of valid environments (e.g., dev, staging, prod)
  final List<Enum> environments;

  /// Current environment the app is running in
  final Enum currentEnvironment;

  /// Base context providers that are always active
  /// These should be lightweight and essential providers
  final List<ContextProvider> baseProviders;

  /// Minimum severity level for automatic reporting
  final ErrorSeverity minSeverity;

  /// Explicitly enable/disable Sentry
  /// If null, Sentry will be enabled if sentryDsn is provided
  final bool? enableSentry;

  /// Callback triggered before sending a report
  /// Return false to cancel the send operation
  final PreSendReportCallback? onPreSendReport;

  /// Callback triggered before sharing a report
  /// Return false to cancel the share operation
  final PreShareReportCallback? onPreShareReport;

  /// Whether Sentry reporting is enabled
  bool get isSentryEnabled =>
      enableSentry ?? (sentryDsn != null && sentryDsn!.isNotEmpty);

  /// Creates a copy of this config with the given fields replaced
  ReportConfig copyWith({
    String? sentryDsn,
    List<Enum>? environments,
    Enum? currentEnvironment,
    List<ContextProvider>? baseProviders,
    ErrorSeverity? minSeverity,
    bool? enableSentry,
    PreSendReportCallback? onPreSendReport,
    PreShareReportCallback? onPreShareReport,
  }) {
    return ReportConfig(
      sentryDsn: sentryDsn ?? this.sentryDsn,
      environments: environments ?? this.environments,
      currentEnvironment: currentEnvironment ?? this.currentEnvironment,
      baseProviders: baseProviders ?? this.baseProviders,
      minSeverity: minSeverity ?? this.minSeverity,
      enableSentry: enableSentry ?? this.enableSentry,
      onPreSendReport: onPreSendReport ?? this.onPreSendReport,
      onPreShareReport: onPreShareReport ?? this.onPreShareReport,
    );
  }

  /// Whether the given severity meets the minimum reporting threshold
  /// and the exception is reportable
  bool shouldSendReport(BaseException e) =>
      e.isReportable && e.severity.index <= minSeverity.index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportConfig &&
          runtimeType == other.runtimeType &&
          sentryDsn == other.sentryDsn &&
          environments == other.environments &&
          currentEnvironment == other.currentEnvironment &&
          minSeverity == other.minSeverity &&
          enableSentry == other.enableSentry;

  @override
  int get hashCode =>
      sentryDsn.hashCode ^
      environments.hashCode ^
      currentEnvironment.hashCode ^
      minSeverity.hashCode ^
      enableSentry.hashCode;
}

/// Example usage:
/// ```dart
/// enum AppEnv { dev, staging, prod }
///
/// final config = ReportConfig(
///   sentryDsn: 'your-dsn',
///   environments: AppEnv.values,
///   currentEnvironment: AppEnv.dev,
///   minSeverity: ErrorSeverity.error,
/// );
/// ```
