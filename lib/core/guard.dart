import 'dart:async';

import 'package:bug_reporting_system/core/client.dart';
import 'package:bug_reporting_system/core/config.dart';
import 'package:bug_reporting_system/core/result.dart';
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:bug_reporting_system/exceptions/data_exception.dart';
import 'package:bug_reporting_system/exceptions/platform_exception.dart';
import 'package:bug_reporting_system/exceptions/unexpected_exception.dart';
import 'package:flutter/services.dart' as service;

/// Guards an async action:
/// - Runs [action]
/// - On success: returns `Ok(value)` and invokes [onSuccess]
/// - On error: normalizes to `BaseException`, reports via client, returns `Err(e)`,
///             and invokes [onError].
Future<Result<T, BaseException>> guard<T>(
  Future<T> Function() action, {
  String? source,
  FutureOr<void> Function(T value)? onSuccess,
  FutureOr<void> Function(BaseException e)? onError,
  bool manual = false,
  Map<String, dynamic> additionalContext = const {},
}) async {
  try {
    final value = await action();
    if (onSuccess != null) await onSuccess(value);
    return Ok<T, BaseException>(value);
  } catch (error, stack) {
    final normalized = normalizeError(
      error,
      stack,
      source: source,
    );
    if (onError != null) await onError(normalized);

    final event = await BugReportClient.instance.createEvent(
      normalized,
      manual: manual,
      additionalContext: additionalContext,
    );
    await BugReportClient.instance.report(event);

    return Err<T, BaseException>(normalized);
  }
}

/// Guards a synchronous computation with the same semantics as [guard].
Result<T, BaseException> guardSync<T>(
  T Function() compute, {
  String? source,
  void Function(T value)? onSuccess,
  void Function(BaseException e)? onError,
  bool manual = false,
  Map<String, dynamic> additionalContext = const {},
}) {
  try {
    final value = compute();
    onSuccess?.call(value);
    return Ok<T, BaseException>(value);
  } catch (error, stack) {
    final normalized = normalizeError(
      error,
      stack,
      source: source,
    );
    onError?.call(normalized);

    // Fire-and-forget reporting for sync guard to avoid blocking UI threads.
    unawaited(() async {
      final event = await BugReportClient.instance.createEvent(
        normalized,
        manual: manual,
        additionalContext: additionalContext,
      );
      await BugReportClient.instance.report(event);
    }());

    return Err<T, BaseException>(normalized);
  }
}

/// Parser helper that catches model/JSON construction errors and throws a typed
/// [ParsingException] (which extends your data exceptions).
T parser<T>(T Function() build, {required Object? data}) {
  try {
    return build();
  } catch (e, s) {
    if (e is BaseException) rethrow;
    throw ParsingException(
      rawData: data,
      targetType: '$T',
      cause: e,
      stack: s,
    );
  }
}

/// Normalizes arbitrary errors into your `BaseException` hierarchy.
///
/// Mapping strategy:
/// - If already `BaseException` => passthrough
/// - If Flutter `PlatformException` => `PlatformOperationException.fromPlatformException`
/// - If `FormatException`/type issues in parser => `ParsingException` (callers should prefer [parser])
/// - Fallback => `UnexpectedException`
BaseException normalizeError(
  Object error,
  StackTrace stack, {
  String? source,
  Severity defaultSeverity = Severity.error,
}) {
  if (error is BaseException) return error;

  if (error is service.PlatformException) {
    return PlatformOperationException.fromPlatformException(
      error,
      operation: source ?? 'unknown_operation',
    );
  }

  if (error is FormatException) {
    return ParsingException(
      rawData: null,
      targetType: 'unknown',
      cause: error,
      stack: stack,
    );
  }

  return UnexpectedException(
    userMessage: 'An unexpected error occurred',
    devMessage:
        source != null ? 'Unexpected error in $source' : 'Unexpected error',
    cause: error,
    stack: stack,
    severity: defaultSeverity,
    metadata: {
      if (source != null) 'source': source,
    },
  );
}
