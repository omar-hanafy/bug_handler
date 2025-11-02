import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:bug_reporting_system/core/client.dart';
import 'package:bug_reporting_system/core/config.dart';
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:bug_reporting_system/exceptions/flutter_error_exception.dart';
import 'package:bug_reporting_system/exceptions/unexpected_exception.dart';
import 'package:flutter/widgets.dart';

/// Application bootstrap for error reporting.
///
/// Wires global error sources to your reporting pipeline:
/// - Flutter framework errors ([FlutterError.onError])
/// - Platform dispatcher errors ([ui.PlatformDispatcher.onError])
/// - Uncaught async errors ([runZonedGuarded])
/// - Other isolate errors (via [Isolate.addErrorListener])
///
/// Usage:
/// ```dart
/// await BugReportBindings.runAppWithReporting(
///   app: () => const MyApp(),
///   config: ClientConfig(
///     environment: kReleaseMode ? 'prod' : 'dev',
///     baseProviders: [AppContextProvider(), DeviceContextProvider()],
///     reporters: [ /* Composite/Console/Sentry adapters at app layer */ ],
///   ),
/// );
/// ```
class BugReportBindings {
  BugReportBindings._();

  static RawReceivePort? _isolatePort;

  /// Bootstraps the app and reporting system.
  static Future<void> runAppWithReporting({
    required Widget Function() app,
    required ClientConfig config,
    bool captureFrameworkErrors = true,
    bool capturePlatformDispatcherErrors = true,
    bool attachIsolateErrorListener = true,
    bool useDefaultFlutterErrorPresentation = true,
  }) async {
    // Initialize the reporting client and pipeline.
    await BugReportClient.instance.initialize(config);

    // Flutter framework errors (build/layout/paint/etc.).
    if (captureFrameworkErrors) {
      final previous = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (useDefaultFlutterErrorPresentation) {
          FlutterError.presentError(details);
        } else {
          // Preserve original handler if caller prefers custom presentation.
          previous?.call(details);
        }
        final exception = _fromFlutterError(details);
        // Fire-and-forget; no need to block UI thread.
        unawaited(_report(exception));
      };
    }

    // Platform dispatcher unhandled errors (e.g., errors bubbling past framework).
    if (capturePlatformDispatcherErrors) {
      final previous = ui.PlatformDispatcher.instance.onError;
      ui.PlatformDispatcher.instance.onError =
          (Object error, StackTrace stack) {
        final exception = _normalize(error, stack);
        final handledByPrevious = previous?.call(error, stack) ?? true;
        unawaited(_report(exception));
        // Returning true marks the error as handled.
        return handledByPrevious && true;
      };
    }

    // Other isolate errors.
    if (attachIsolateErrorListener) {
      _attachIsolateListener();
    }

    // Catch all remaining async uncaught errors in the root zone.
    runZonedGuarded<void>(
      () => runApp(app()),
      (Object error, StackTrace stack) {
        final exception = _normalize(error, stack);
        unawaited(_report(exception));
      },
    );
  }

  // === Internals =============================================================

  static void _attachIsolateListener() {
    // Avoid attaching multiple listeners if called more than once.
    if (_isolatePort != null) return;

    _isolatePort = RawReceivePort((dynamic data) {
      // Isolate error payload shape is typically [error, stackTraceString]
      if (data is List && data.length >= 2) {
        final error = data[0] as Object;
        final stack = switch (data[1]) {
          final StackTrace s => s,
          _ => StackTrace.fromString(data[1]?.toString() ?? ''),
        };
        final exception = _normalize(error, stack);
        unawaited(_report(exception));
      }
    });

    Isolate.current.addErrorListener(_isolatePort!.sendPort);
  }

  /// Converts [FlutterErrorDetails] to a [BaseException] you can report.
  static BaseException _fromFlutterError(FlutterErrorDetails details) {
    // Prefer a dedicated Flutter exception type when available.
    return FlutterErrorException(details);
  }

  /// Normalizes any error into your [BaseException] hierarchy.
  static BaseException _normalize(Object error, StackTrace stack) {
    if (error is BaseException) return error;
    // Fall back to your UnexpectedException for unknown types.
    return UnexpectedException(
      cause: error,
      stack: stack,
      devMessage: 'Uncaught asynchronous error',
    );
  }

  /// Creates and sends the report through the configured pipeline.
  static Future<void> _report(BaseException exception) async {
    try {
      final event = await BugReportClient.instance.createEvent(exception);
      await BugReportClient.instance.report(event);
    } catch (_) {
      // Intentionally ignore; avoid crashing the app due to reporting failures.
    }
  }
}
