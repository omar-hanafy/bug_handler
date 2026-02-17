import 'dart:developer';

import 'package:bug_handler/config/report_config.dart';
import 'package:bug_handler/context/provider.dart';
import 'package:bug_handler/core/bug_reporter.dart';
import 'package:bug_handler/core/report.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:bug_handler/reporters/manual_reporter.dart';
import 'package:bug_handler/reporters/reporter.dart';
import 'package:bug_handler/reporters/sentry_reporter.dart';

export 'package:sentry_flutter/sentry_flutter.dart'
    hide
        HttpHeaderUtils,
        HttpSanitizer,
        OnBeforeCaptureLog,
        OnBeforeSendEvent,
        SanitizedSentryRequest,
        SdkLifecycleCallback,
        SdkLifecycleEvent,
        SdkLifecycleRegistry,
        SentrySpanData,
        SentrySpanDescriptions,
        SentrySpanOperations,
        SentryTraceOrigins,
        UrlDetails,
        formatDateAsIso8601WithMillisPrecision,
        getBreadcrumbLogLevelFromHttpStatusCode,
        getUtcDateTime,
        jsonSerializationFallback;

/// Core bug reporting system that manages configuration, contexts, and reporting
class BugReporter {
  BugReporter._();

  static final instance = BugReporter._();

  ReportConfig? _config;
  final List<ContextProvider> _additionalProviders = [];
  Reporter? _reporter;

  bool isInitialized() => _config != null;

  /// Initialize the bug reporting system
  /// Must be called before using any reporting features
  static Future<void> initialize(
    void Function() start, {
    required ReportConfig config,
  }) async {
    if (instance.isInitialized()) {
      throw StateError('BugReporter already initialized');
    }

    final reporter = await _initializeReporter(config, start);

    instance
      .._config = config
      .._reporter = reporter;
  }

  static Future<Reporter> _initializeReporter(
    ReportConfig config,
    void Function() start,
  ) async {
    if (!config.isSentryEnabled) {
      start.call();
      return ManualReporter();
    }

    try {
      await SentryFlutter.init(
        (options) {
          options
            ..dsn = config.sentryDsn
            ..environment = config.currentEnvironment.toString()
            // Let Sentry handle most contexts automatically
            ..attachScreenshot =
                false // We handle this manually
            ..attachThreads = false;
        },
        appRunner: start,
      );
      return SentryReporter();
    } catch (_) {
      // Fallback to manual reporting if Sentry fails
      start.call();
      return ManualReporter();
    }
  }

  /// Add a context provider after initialization
  /// Useful for providers that need app initialization (e.g., user data)
  Future<void> addContextProvider(ContextProvider provider) async {
    if (_additionalProviders.contains(provider)) return;
    _additionalProviders.add(provider);
  }

  /// Remove a context provider
  void removeContextProvider(ContextProvider provider) {
    _additionalProviders.remove(provider);
  }

  /// Clear all additional context providers
  void clearAdditionalProviders() {
    _additionalProviders.clear();
  }

  /// Create a report for an exception
  Future<Report> createReport(
    BaseException exception, {
    bool manualReport = false,
  }) async {
    final config = _config;
    if (config == null) {
      throw StateError('BugReporter not initialized');
    }

    // Collect context from all relevant providers
    final context = <String, dynamic>{};

    // Always include base providers
    for (final provider in config.baseProviders) {
      try {
        final data = await provider.getData();
        if (provider.validateData(data)) {
          context[provider.name] = data;
        }
      } catch (_) {
        // Skip failed providers
      }
    }

    // Include additional providers if manual report or not manual-only
    for (final provider in _additionalProviders) {
      if (manualReport || !provider.manualReportOnly) {
        try {
          final data = await provider.getData();
          if (provider.validateData(data)) {
            context[provider.name] = data;
          }
        } catch (_) {
          // Skip failed providers
        }
      }
    }

    if (!exception.isReportable) {
      // printing warning here before sending the report.
      log('Warning: Exception ${exception.runtimeType} is not reportable');
    }

    return Report(
      exception: exception,
      context: context,
      reporter: _reporter ?? ManualReporter(),
      onPreSendReport: config.onPreSendReport,
      onPreShareReport: config.onPreShareReport,
    );
  }

  /// Report an exception
  Future<Report?> reportException(
    BaseException exception, {
    bool force = false,
  }) async {
    final config = _config;
    if (config == null) return null;

    if (!exception.isReportable && !force) {
      log('Skipping report creation: Exception is not reportable');
      return null;
    }

    final report = await createReport(exception);
    final shouldSendReport = force || config.shouldSendReport(exception);

    if (shouldSendReport) {
      await report.send();
    } else {
      log('Report not sent: Did not meet sending criteria');
    }

    return report;
  }
}
