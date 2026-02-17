import 'dart:developer';

import 'package:bug_handler/config/report_config.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:bug_handler/reporters/reporter.dart';
import 'package:flutter_helper_utils/flutter_helper_utils.dart';
import 'package:meta/meta.dart';

/// Represents a bug report with all necessary context and data
@immutable
class Report {
  const Report({
    required this.exception,
    required this.context,
    required this.reporter,
    this.timestamp,
    this.onPreSendReport,
    this.onPreShareReport,
  });

  /// The exception that triggered this report
  final BaseException exception;

  /// Collected context data from providers
  final Map<String, dynamic> context;

  /// Reporter instance to use for this report
  final Reporter reporter;

  /// When the report was created
  final DateTime? timestamp;

  /// Callback triggered before sending the report
  final PreSendReportCallback? onPreSendReport;

  /// Callback triggered before sharing the report
  final PreShareReportCallback? onPreShareReport;

  /// Convert report to a map for serialization
  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      'exception': {
        'type': exception.runtimeType.toString(),
        'userMessage': exception.userMessage,
        'devMessage': exception.devMessage,
        'severity': exception.severity.name,
        'stackTrace': exception.stack?.toString(),
        'metadata': exception.metadata,
        'isReportable': exception.isReportable,
        if (exception.cause != null)
          'cause': {
            'type': exception.cause.runtimeType.toString(),
            'message': exception.cause.toString(),
          },
      },
      'context': context,
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
    }.encodableCopy;

    log('Prepared Bug Report Data!');
    log(data.encodedJsonString);
    return data;
  }

  /// Convert to JSON string
  String toJson() => toMap().encodedJsonString;

  /// Send report using configured reporter
  Future<void> send() async {
    if (!exception.isReportable) {
      log('Skipping report send: Exception is not reportable');
      return; // Silent return instead of throwing
    }

    // Invoke pre-send callback if provided
    if (onPreSendReport != null) {
      final shouldProceed = await onPreSendReport!(this);
      if (!shouldProceed) {
        log('Report send cancelled by onPreSendReport callback');
        return;
      }
    }

    await reporter.sendReport(this);
  }

  /// Share report manually (usually as a file)
  Future<void> share() async {
    if (!exception.isReportable) {
      log('Skipping report share: Exception is not reportable');
      return; // Silent return instead of throwing
    }

    // Invoke pre-share callback if provided
    if (onPreShareReport != null) {
      final shouldProceed = await onPreShareReport!(this);
      if (!shouldProceed) {
        log('Report share cancelled by onPreShareReport callback');
        return;
      }
    }

    await reporter.shareReport(this);
  }

  @override
  String toString() =>
      '''
Report {
  Exception: ${exception.runtimeType}
  User Message: ${exception.userMessage}
  Dev Message: ${exception.devMessage}
  Severity: ${exception.severity}
  Context: ${context.keys.join(', ')}
}''';
}
