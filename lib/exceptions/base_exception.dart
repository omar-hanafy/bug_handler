import 'package:meta/meta.dart';

import '../config/severity.dart';

// new bug repoort system has this base BaseException class
/// Base class for all exceptions that can be reported
@immutable
abstract class BaseException implements Exception {
  const BaseException({
    required this.userMessage,
    required this.devMessage,
    this.cause,
    this.stack,
    this.metadata = const {},
    this.severity = ErrorSeverity.error,
    this.isReportable = true,
  });

  /// Message shown to users
  final String userMessage;

  /// Message for developers/debugging
  final String devMessage;

  /// Original error that caused this exception
  final Object? cause;

  /// Stack trace where the error occurred
  final StackTrace? stack;

  /// Additional data specific to this exception
  final Map<String, dynamic> metadata;

  /// Severity level of this exception
  final ErrorSeverity severity;

  final bool isReportable;

  @override
  String toString() =>
      '''
$runtimeType
User Message: $userMessage
Dev Message: $devMessage
${cause != null ? 'Cause: $cause' : ''}
${stack != null ? 'Stack Trace:\n$stack' : ''}
''';
}
