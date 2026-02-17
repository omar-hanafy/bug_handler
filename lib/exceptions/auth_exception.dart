import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

class AuthException extends BaseException {
  AuthException({
    required super.userMessage,
    String? devMessage,
    this.errorCode,
    this.provider,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
  }) : super(
         devMessage: devMessage ?? userMessage,
         severity: ErrorSeverity.error,
         metadata: {
           if (errorCode != null) 'errorCode': errorCode,
           if (provider != null) 'provider': provider,
           ...?additionalMetadata,
         },
       );

  final String? errorCode;
  final String? provider;
}

class TokenException extends AuthException {
  TokenException({
    String? userMessage,
    required super.devMessage,
    super.errorCode,
    super.provider,
    super.cause,
    super.stack,
  }) : super(
         userMessage:
             userMessage ?? 'Your session has expired. Please sign in again',
       );
}
