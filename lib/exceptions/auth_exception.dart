import 'package:bug_handler/core/config.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Authentication/authorization related failures.
@immutable
class AuthException extends BaseException {
  /// Creates an auth exception with optional vendor-specific metadata.
  AuthException({
    required super.userMessage,
    String? devMessage,
    this.errorCode,
    this.provider,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity,
    super.isReportable,
  }) : super(
          devMessage: devMessage ?? userMessage,
          metadata: {
            if (errorCode != null) 'errorCode': errorCode,
            if (provider != null) 'provider': provider,
            ...metadata,
          },
        );

  /// Provider-specific error code, when available.
  final String? errorCode;

  /// Name of the identity provider that produced the error.
  final String? provider;
}

/// Specialized exception for token/session lifecycle issues.
@immutable
class TokenException extends AuthException {
  /// Creates a token exception for session expiry or invalid tokens.
  TokenException({
    String? userMessage,
    required String super.devMessage,
    super.errorCode,
    super.provider,
    super.cause,
    super.stack,
    super.metadata,
    super.isReportable,
  }) : super(
          userMessage:
              userMessage ?? 'Your session has expired. Please sign in again.',
          severity: Severity.error,
        );
}
