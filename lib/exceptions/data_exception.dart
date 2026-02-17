import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

class DataProcessingException extends BaseException {
  DataProcessingException({
    required super.userMessage,
    required super.devMessage,
    this.data,
    this.operation,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
  }) : super(
         severity: ErrorSeverity.error,
         metadata: {
           if (operation != null) 'operation': operation,
           if (data != null) 'rawData': data.toString(),
           ...?additionalMetadata,
         },
       );

  final Object? data;
  final String? operation;
}

class ParsingException extends DataProcessingException {
  ParsingException({
    required Object? rawData,
    required String targetType,
    super.cause,
    super.stack,
  }) : super(
         userMessage: 'Unable to process data',
         devMessage: 'Failed to parse $targetType',
         data: rawData,
         operation: 'parsing',
         additionalMetadata: {'targetType': targetType},
       );
}
