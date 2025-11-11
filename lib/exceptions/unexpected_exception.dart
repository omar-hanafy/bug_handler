import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Generic fallback for uncaught/unknown errors.
/// Helpful during normalization in guard/pipeline layers.
@immutable
class UnexpectedException extends BaseException {
  /// Creates a catch-all exception when no specific domain type applies.
  UnexpectedException({
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity,
    super.isReportable,
  }) : super(
          userMessage: userMessage ?? 'An unexpected error occurred.',
          devMessage: devMessage ?? 'Unexpected error.',
          metadata: {
            'errorType': cause?.runtimeType.toString(),
            'originalError': cause?.toString(),
            ...metadata,
          },
        );
}
