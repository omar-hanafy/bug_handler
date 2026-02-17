import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/core/bug_reporter.dart';
import 'package:bug_handler/core/report.dart';
import 'package:bug_handler/reporters/reporter.dart';
import 'package:share_plus/share_plus.dart';

/// Reporter implementation that sends reports to Sentry.
/// Leverages Sentry's automatic data collection capabilities while adding
/// our custom context data when needed.

class SentryReporter extends Reporter {
  @override
  Future<bool> sendReport(Report report) async {
    try {
      final event = _createSentryEvent(report);
      if (event != null) {
        await Sentry.captureEvent(
          event,
          stackTrace: report.exception.stack,
          hint: Hint.withMap(report.toMap()),
          withScope: (scope) {
            scope.level = _getSentryLevel(report.exception.severity);
            _addCustomContext(scope, report);
          },
        );
      } else {
        await Sentry.captureException(
          report.exception.cause ?? report.exception,
          stackTrace: report.exception.stack,
          hint: Hint.withMap(report.toMap()),
          withScope: (scope) {
            scope.level = _getSentryLevel(report.exception.severity);
            _addCustomContext(scope, report);
          },
        );
      }
      return true;
    } catch (e) {
      return shareReport(report);
    }
  }

  SentryEvent? _createSentryEvent(Report report) {
    try {
      final exception = report.exception;
      return SentryEvent(
        eventId: SentryId.newId(),
        throwable: exception.cause ?? exception,
        timestamp: report.timestamp,
        contexts: _createNonDuplicateContexts(report),
        type: exception.runtimeType.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  // Only add contexts that Sentry doesn't already collect
  Contexts _createNonDuplicateContexts(Report report) {
    final contexts = Contexts();
    final customContexts = <String, dynamic>{};

    // Add non-duplicate context data
    for (final entry in report.context.entries) {
      // Skip contexts that Sentry auto-collects
      if (!_isAutoCollectedContext(entry.key) && entry.value != null) {
        customContexts[entry.key] = entry.value;
      }
    }

    if (customContexts.isNotEmpty) contexts['custom'] = customContexts;

    return contexts;
  }

  bool _isAutoCollectedContext(String key) {
    // List of contexts Sentry automatically collects
    final autoCollectedKeys = {
      'device',
      'os',
      'browser',
      'runtime',
      'app',
      'gpu',
      'culture',
      'environment',
      'release',
      'user',
      'request',
      'timezone',
      'language',
      'platform',
      'version',
    };

    return autoCollectedKeys.contains(key.toLowerCase());
  }

  void _addCustomContext(Scope scope, Report report) {
    // Only add tags that provide value beyond Sentry's auto-collection
    scope
      ..setTag('has_user_message', 'true')
      ..setTag('has_dev_message', 'true');

    // Add any custom non-duplicate tags
    for (final entry in report.context.entries) {
      if (!_isAutoCollectedContext(entry.key) && entry.value != null) {
        scope.setTag('custom.${entry.key}', entry.value.toString());
      }
    }
  }

  SentryLevel _getSentryLevel(ErrorSeverity severity) {
    return switch (severity) {
      ErrorSeverity.critical => SentryLevel.fatal,
      ErrorSeverity.error => SentryLevel.error,
      ErrorSeverity.warning => SentryLevel.warning,
      ErrorSeverity.info => SentryLevel.info,
    };
  }

  @override
  Future<bool> shareReport(Report report) async {
    final reportFile = await generateReportFile(report);
    try {
      await Share.shareXFiles(
        [XFile(reportFile.path)],
        subject: 'Error Report',
        text: 'Error report details attached',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
