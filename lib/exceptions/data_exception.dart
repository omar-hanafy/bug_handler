import 'package:bug_handler/core/config.dart' show Severity;
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Data processing/generation pipeline failures (IO, transforms, mapping).
@immutable
class DataProcessingException extends BaseException {
  /// Creates a data processing exception, optionally capturing raw input.
  DataProcessingException({
    required super.userMessage,
    required super.devMessage,
    this.data,
    this.operation,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity,
    super.isReportable,
  }) : super(
          metadata: {
            if (operation != null) 'operation': operation,
            if (data != null) 'rawData': data,
            ...metadata,
          },
        );

  /// Raw data that triggered the failure, if available.
  final Object? data;

  /// Logical operation that was running when the error occurred.
  final String? operation;
}

/// Safe parsing failure for models or config.
@immutable
class ParsingException extends DataProcessingException {
  /// Creates a parsing exception that wraps the failing [rawData].
  ParsingException({
    required Object? rawData,
    required String targetType,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.isReportable,
  }) : super(
          userMessage: 'Unable to process data.',
          devMessage: 'Failed to parse $targetType',
          data: rawData,
          operation: 'parsing',
          metadata: {
            'targetType': targetType,
            ...metadata,
          },
          severity: Severity.error,
        );
}
