import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

class InitializationException extends BaseException {
  InitializationException({
    required String component,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
  }) : super(
         userMessage: userMessage ?? 'Failed to initialize application',
         devMessage: devMessage ?? 'Initialization failed for: $component',
         severity: ErrorSeverity.critical,
         metadata: {
           'component': component,
           ...?additionalMetadata,
         },
       );
}

class ComponentNotInitializedException extends InitializationException {
  ComponentNotInitializedException({
    required super.component,
    super.cause,
    super.stack,
  }) : super(
         userMessage: 'Application setup incomplete',
         devMessage: '$component not initialized',
       );
}
