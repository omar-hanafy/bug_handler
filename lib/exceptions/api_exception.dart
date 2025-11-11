import 'package:bug_handler/core/config.dart' show Severity;
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:bug_handler/helpers.dart';
import 'package:meta/meta.dart';

/// Exception representing HTTP / API-layer failures.
/// Enriches context with normalized HTTP status metadata.
@immutable
class ApiException extends BaseException {
  /// Creates an API exception enriched with normalized HTTP status metadata.
  ApiException({
    required this.httpStatusInfo,
    String? endpoint,
    String? method,
    Map<String, dynamic> requestHeaders = const {},
    Object? requestBody,
    Map<String, dynamic> responseHeaders = const {},
    Object? responseBody,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    Severity? severity,
    super.isReportable,
  }) : super(
          userMessage: userMessage ?? httpStatusInfo.statusUserMessage,
          devMessage: devMessage ??
              'HTTP ${httpStatusInfo.statusCode} ${method ?? ''} ${endpoint ?? ''}'
                  .trim(),
          metadata: {
            'http': {
              ...httpStatusInfo.toMap(),
              if (endpoint != null) 'endpoint': endpoint,
              if (method != null) 'method': method,
              if (requestHeaders.isNotEmpty) 'requestHeaders': requestHeaders,
              if (requestBody != null) 'requestBody': requestBody,
              if (responseHeaders.isNotEmpty)
                'responseHeaders': responseHeaders,
              if (responseBody != null) 'responseBody': responseBody,
            },
            ...metadata,
          },
          severity: severity ?? httpStatusInfo.errorSeverity,
        );

  /// Normalized view of status code + semantic flags.
  final HttpStatusCodeInfo httpStatusInfo;
}
