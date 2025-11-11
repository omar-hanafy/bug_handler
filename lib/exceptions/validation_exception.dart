import 'package:bug_handler/core/config.dart' show Severity;
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Validation failures for inputs, forms, or domain constraints.
@immutable
class ValidationException extends BaseException {
  /// Creates a validation exception summarizing [validationErrors] for callers.
  ValidationException({
    required super.userMessage,
    String? devMessage,
    Map<String, dynamic> validationErrors = const {},
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity = Severity.warning,
    super.isReportable = false,
  }) : super(
          devMessage: devMessage ?? 'Validation failed.',
          metadata: {
            if (validationErrors.isNotEmpty)
              'validationErrors': validationErrors,
            ...metadata,
          },
        );
}
