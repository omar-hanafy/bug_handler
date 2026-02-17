import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:flutter/material.dart';

class FlutterErrorException extends BaseException {
  FlutterErrorException(this.flutterError)
    : super(
        userMessage: 'An unexpected error occurred in the application',
        devMessage: 'Flutter framework error: ${flutterError.exception}',
        cause: flutterError.exception,
        stack: flutterError.stack,
        severity: ErrorSeverity.error,
        metadata: _createMetadata(flutterError),
      );

  final FlutterErrorDetails flutterError;

  static Map<String, dynamic> _createMetadata(FlutterErrorDetails details) {
    return {
      'library': details.library ?? 'Unknown',
      'context': _getContextData(details.context),
      'silent': details.silent,
      if (details.informationCollector != null)
        'additionalInfo': details.informationCollector!().toString(),
    };
  }

  static Map<String, dynamic> _getContextData(DiagnosticsNode? context) {
    if (context == null) return {};

    return {
      'name': context.name,
      'allowWrap': context.allowWrap,
      'allowNameWrap': context.allowNameWrap,
      'allowTruncate': context.allowTruncate,
      'value': context.value?.toString(),
      'description': context.toDescription(),
      'style': context.style.toString(),
      'showName': context.showName,
      'level': context.level.toString(),
    };
  }

  @override
  String toString() =>
      '''
${super.toString()}
Flutter Error Details:
  Library: ${flutterError.library}
  Silent: ${flutterError.silent}
  Context: ${flutterError.context}
''';
}
