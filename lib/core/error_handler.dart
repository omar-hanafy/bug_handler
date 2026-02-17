import 'dart:async';
import 'dart:developer';

import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/core/bug_reporter.dart';
import 'package:bug_handler/core/report.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:bug_handler/exceptions/data_exception.dart';
import 'package:bug_handler/exceptions/unexpected_exception.dart';
// to use me --> import 'package:bug_handler/core/error_handler.dart';

typedef ExceptionCallback<T extends Object?> =
    FutureOr<T> Function(BaseException exception);

class ReportResult<T extends Object?> {
  ReportResult({
    required this.report,
    required this.didThrow,
    required this.didReport,
    required this.onErrorResult,
    required this.data,
    required this.exception,
  });

  final Report? report;
  final bool didThrow;
  final bool didReport;
  final Object? onErrorResult;
  final BaseException? exception;
  final T? data;
}

/// Utility class for handling errors and exceptions
class ErrorHandler {
  /// For direct error handling with maximum control.
  ///
  /// ```dart
  /// try {
  ///   await riskyOperation();
  /// } catch (error, stack) {
  ///   final (report, didThrow) = await handleError(
  ///     error,
  ///     stack,
  ///     source: 'PaymentScreen',
  ///     userMessage: 'Payment failed, please try again',
  ///     devMessage: 'Payment gateway timeout',
  ///     severity: ErrorSeverity.critical,
  ///     onError: (exception) async {
  ///       await showErrorDialog(exception.userMessage);
  ///       await analytics.logPaymentError(exception);
  ///     },
  ///   );
  /// }
  /// ```
  /// Handles errors by optionally reporting them and executing callbacks.
  ///
  /// Returns a [ReportResult] containing information about the error handling process.
  ///
  /// Parameters:
  /// - [error]: The original error or exception
  /// - [stack]: The stack trace
  /// - [source]: The source/context where the error occurred
  /// - [userMessage]: User-friendly error message
  /// - [devMessage]: Developer-focused error details
  /// - [shouldReport]: Optional callback to determine if error should be reported
  /// - [severity]: Error severity level
  /// - [onError]: Optional callback executed when error occurs
  static Future<ReportResult<T>> handle<T>(
    Object error,
    StackTrace stack, {
    String? source,
    String? userMessage,
    String? devMessage,
    FutureOr<bool> Function(BaseException e)? shouldReport,
    ErrorSeverity severity = ErrorSeverity.error,
    ExceptionCallback? onError,
  }) async {
    final exception = error is BaseException
        ? error
        : UnexpectedException(
            userMessage: userMessage,
            devMessage:
                devMessage ??
                (source != null
                    ? 'Unexpected error in $source'
                    : 'Unexpected error'),
            cause: error,
            stack: stack,
            severity: severity,
          );

    Object? onErrorResult;
    try {
      onErrorResult = await onError?.call(exception);
    } catch (e) {
      log('[ErrorHandler] Error in onError callback: $e');
    }

    Report? report;
    var didReport = false;

    final shouldReportResult = await shouldReport?.call(exception) ?? true;
    if (shouldReportResult && exception.isReportable) {
      try {
        report = await BugReporter.instance.createReport(exception);
        try {
          await report.send();
          didReport = true;
        } catch (e) {
          log('[ErrorHandler] Failed to send bug report: $e');
        }
      } catch (e) {
        log('[ErrorHandler] Failed to create bug report: $e');
      }
    }

    return ReportResult(
      report: report,
      didThrow: true,
      exception: exception,
      didReport: didReport,
      onErrorResult: onErrorResult,
      data: null,
    );
  }

  /// For clean, declarative error handling of async operations.
  ///
  /// ```dart
  /// // Simple Usage
  /// final (report, didThrow) result = await wrapper(
  ///   () => api.fetchData(),
  ///   source: 'DataService',
  /// );
  ///
  /// // Advanced Usage with State Management
  /// Future<void> processPayment(String orderId) async {
  ///   final (report, didThrow) = await wrapper(
  ///     () => paymentGateway.process(orderId),
  ///     source: 'PaymentProcessor',
  ///     onSuccess: (receipt) async {
  ///       state = PaymentState.success(receipt);
  ///       await analytics.logPaymentSuccess(receipt);
  ///     },
  ///     onError: (exception) async {
  ///       state = PaymentState.failed(exception.message);
  ///       if (exception is PaymentDeclinedException) {
  ///         await showDeclinedDialog();
  ///       }
  ///     },
  ///   );
  ///
  ///   if (didThrow) {
  ///     // do extra stuff if needed.
  ///     // ...
  ///
  ///      /// u usually gonna need the didThrow just to return, in case u wanna stop the operation, and since any handling done through the wrapper might be enough for u, however it depends on ur case.
  ///     return;
  ///   }
  ///
  ///   // Continue with post-payment operations
  /// }
  /// ```
  static Future<ReportResult<T>> wrap<T>(
    Future<T> Function() action, {
    FutureOr<void> Function(T result)? onSuccess,
    FutureOr<bool> Function(BaseException e)? shouldReport,
    String? source,
    ExceptionCallback? onError,
  }) async {
    try {
      final result = await action();
      if (onSuccess != null) await onSuccess(result);
      return ReportResult(
        report: null,
        exception: null,
        didThrow: false,
        didReport: false,
        onErrorResult: null,
        data: result,
      );
    } catch (e, stack) {
      return handle(
        e,
        stack,
        source: source,
        shouldReport: shouldReport,
        onError: onError,
      );
    }
  }
}

/// Global method to handle an error check usage in [ErrorHandler].
Future<ReportResult> handleError(
  Object error,
  StackTrace stack, {
  String? source,
  String? userMessage,
  String? devMessage,
  ErrorSeverity severity = ErrorSeverity.error,
  ExceptionCallback? onError,
  FutureOr<bool> Function(BaseException e)? shouldReport,
}) {
  return ErrorHandler.handle(
    error,
    stack,
    source: source,
    userMessage: userMessage,
    devMessage: devMessage,
    severity: severity,
    onError: onError,
    shouldReport: shouldReport,
  );
}

/// Global method to wrap an async operation with error handling check usage in [ErrorHandler].
Future<ReportResult<T>> wrapper<T>(
  Future<T> Function() action, {
  FutureOr<void> Function(T result)? onSuccess,
  FutureOr<bool> Function(BaseException e)? shouldReport,
  String? source,
  ExceptionCallback? onError,
}) {
  return ErrorHandler.wrap<T>(
    action,
    onSuccess: onSuccess,
    source: source,
    onError: onError,
    shouldReport: shouldReport,
  );
}

/// For safe data parsing with automatic error transformation.
///
/// ```dart
/// class ProductModel {
///   final String id;
///   final double price;
///   final List<String> categories;
///
///   ProductModel.fromJson(Map<String, dynamic> json) {
///     return parser(() {
///       id = json['id'] as String;
///       price = (json['price'] as num).toDouble();
///       categories = (json['categories'] as List).cast<String>();
///     },
///      data: json,
///      );
///   }
/// }
/// ```
T parser<T>(T Function() action, {required Object? data}) {
  try {
    return action();
  } catch (e, s) {
    if (e is BaseException) rethrow;
    throw ParsingException(cause: e, stack: s, rawData: data, targetType: '$T');
  }
}
