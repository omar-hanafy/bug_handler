import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

enum PlatformPaymentType {
  applePay,
  googlePay,
  samsungPay,
  huaweiPay,
  miPay,
  paypalSDK,
  stripeSdk,
  amazonPay
  ;

  String get displayName {
    return switch (this) {
      applePay => 'Apple Pay',
      googlePay => 'Google Pay',
      samsungPay => 'Samsung Pay',
      huaweiPay => 'Huawei Pay',
      miPay => 'Mi Pay',
      paypalSDK => 'PayPal',
      stripeSdk => 'Stripe',
      amazonPay => 'Amazon Pay',
    };
  }

  bool get isRegionDependent {
    return switch (this) {
      applePay => true,
      googlePay => true,
      samsungPay => true,
      huaweiPay => true,
      miPay => true,
      paypalSDK => false,
      stripeSdk => false,
      amazonPay => true,
    };
  }

  bool get requiresDeviceCapability {
    return switch (this) {
      applePay => true,
      googlePay => true,
      samsungPay => true,
      huaweiPay => true,
      miPay => true,
      paypalSDK => false,
      stripeSdk => false,
      amazonPay => false,
    };
  }
}

class PlatformPaymentException extends BaseException {
  PlatformPaymentException({
    required this.type,
    this.errorCode,
    String? userMessage,
    String? devMessage,
    this.transactionId,
    this.amount,
    this.currency,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
  }) : super(
         userMessage: userMessage ?? _getDefaultUserMessage(type),
         devMessage:
             devMessage ?? '${type.displayName} payment failed: $errorCode',
         severity: ErrorSeverity.error,
         metadata: {
           'paymentType': type.name,
           'errorCode': errorCode,
           if (transactionId != null) 'transactionId': transactionId,
           if (amount != null) 'amount': amount,
           if (currency != null) 'currency': currency,
           ...?additionalMetadata,
         },
       );

  // Common error factory constructors
  factory PlatformPaymentException.cancelled({
    required PlatformPaymentType type,
    String? transactionId,
    Object? cause,
    StackTrace? stack,
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'payment_cancelled',
      userMessage: 'Payment was cancelled',
      devMessage: '${type.displayName} payment cancelled by user',
      transactionId: transactionId,
      cause: cause,
      stack: stack,
    );
  }

  factory PlatformPaymentException.notAvailable({
    required PlatformPaymentType type,
    Object? cause,
    StackTrace? stack,
  }) {
    final message = type.requiresDeviceCapability
        ? '${type.displayName} is not available on this device'
        : '${type.displayName} is currently unavailable';

    return PlatformPaymentException(
      type: type,
      errorCode: 'payment_not_available',
      userMessage: message,
      devMessage: '${type.displayName} payment method not available',
      cause: cause,
      stack: stack,
    );
  }

  factory PlatformPaymentException.notSupported({
    required PlatformPaymentType type,
    Object? cause,
    StackTrace? stack,
  }) {
    final message = type.isRegionDependent
        ? '${type.displayName} is not supported in your region'
        : '${type.displayName} is not supported';

    return PlatformPaymentException(
      type: type,
      errorCode: 'payment_not_supported',
      userMessage: message,
      devMessage: '${type.displayName} payment method not supported',
      cause: cause,
      stack: stack,
    );
  }

  factory PlatformPaymentException.invalidConfiguration({
    required PlatformPaymentType type,
    String? details,
    Object? cause,
    StackTrace? stack,
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'invalid_configuration',
      userMessage: 'Payment system is not properly configured',
      devMessage:
          'Invalid ${type.displayName} configuration${details != null ? ': $details' : ''}',
      cause: cause,
      stack: stack,
      additionalMetadata: details != null
          ? {'configurationDetails': details}
          : null,
    );
  }

  factory PlatformPaymentException.insufficientFunds({
    required PlatformPaymentType type,
    String? transactionId,
    double? amount,
    String? currency,
    Object? cause,
    StackTrace? stack,
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'insufficient_funds',
      userMessage: 'Insufficient funds to complete the payment',
      devMessage: 'Insufficient funds for ${type.displayName} payment',
      transactionId: transactionId,
      amount: amount,
      currency: currency,
      cause: cause,
      stack: stack,
    );
  }

  factory PlatformPaymentException.authenticationFailed({
    required PlatformPaymentType type,
    String? transactionId,
    String? details,
    Object? cause,
    StackTrace? stack,
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'authentication_failed',
      userMessage: 'Payment authentication failed',
      devMessage:
          '${type.displayName} authentication failed${details != null ? ': $details' : ''}',
      transactionId: transactionId,
      cause: cause,
      stack: stack,
      additionalMetadata: details != null ? {'authDetails': details} : null,
    );
  }

  factory PlatformPaymentException.networkError({
    required PlatformPaymentType type,
    String? transactionId,
    Object? cause,
    StackTrace? stack,
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'network_error',
      userMessage: 'Network error occurred during payment',
      devMessage: 'Network error during ${type.displayName} payment',
      transactionId: transactionId,
      cause: cause,
      stack: stack,
    );
  }

  final PlatformPaymentType type;
  final String? errorCode;
  final String? transactionId;
  final double? amount;
  final String? currency;

  static String _getDefaultUserMessage(PlatformPaymentType type) {
    return '${type.displayName} payment failed';
  }

  @override
  String toString() =>
      '''
${super.toString()}
Payment Type: ${type.displayName}
Error Code: $errorCode
${transactionId != null ? 'Transaction ID: $transactionId' : ''}
${amount != null ? 'Amount: $amount ${currency ?? ''}' : ''}
''';
}
