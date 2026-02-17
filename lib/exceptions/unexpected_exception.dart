import 'package:bug_handler/exceptions/base_exception.dart';

class UnexpectedException extends BaseException {
  UnexpectedException({
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    super.isReportable,
    super.severity,
    Map<String, dynamic> metadata = const {},
  }) : super(
         userMessage: userMessage ?? 'An unexpected error occurred',
         devMessage: devMessage ?? 'Unexpected error',
         metadata: {
           ...metadata,
           'originalError': cause?.toString(),
           'errorType': cause?.runtimeType.toString(),
         },
       );
}
