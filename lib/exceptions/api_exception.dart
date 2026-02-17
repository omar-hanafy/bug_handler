import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:bug_handler/helpers.dart';

/// Exception class for handling API-related errors with enhanced features
class ApiException extends BaseException {
  ApiException({
    required this.httpStatusInfo,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    super.metadata = const {},
    super.severity = ErrorSeverity.error,
    super.isReportable,
  }) : super(
         userMessage: userMessage ?? httpStatusInfo.statusUserMessage,
         devMessage: devMessage ?? httpStatusInfo.statusDevMessage,
       );

  final HttpStatusCodeInfo httpStatusInfo;

  @override
  Map<String, dynamic> get metadata => {
    ...super.metadata,
    'timestamp': DateTime.now().toIso8601String(),
    'httpStatusInfo': httpStatusInfo.toMap(),
  };
}
