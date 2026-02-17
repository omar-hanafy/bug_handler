import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

class ValidationException extends BaseException {
  ValidationException({
    required super.userMessage,
    String? devMessage,
    Map<String, dynamic>? validationErrors,
    super.cause,
    super.stack,
  }) : super(
         devMessage: devMessage ?? 'Validation failed',
         severity: ErrorSeverity.warning,
         metadata: {
           'validationErrors': validationErrors,
         },
       );
}
