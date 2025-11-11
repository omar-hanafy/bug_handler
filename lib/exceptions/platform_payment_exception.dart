import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Supported platform payment providers. Extend as needed.
enum PlatformPaymentType {
  /// Apple Pay integration.
  applePay,

  /// Google Pay integration.
  googlePay,

  /// Samsung Pay integration.
  samsungPay,

  /// Huawei Pay integration.
  huaweiPay,

  /// Xiaomi Mi Pay integration.
  miPay,

  /// PayPal SDK integration.
  paypalSDK,

  /// Stripe SDK integration.
  stripeSdk,

  /// Amazon Pay integration.
  amazonPay;

  /// Human-friendly label for the payment provider.
  String get displayName {
    switch (this) {
      case PlatformPaymentType.applePay:
        return 'Apple Pay';
      case PlatformPaymentType.googlePay:
        return 'Google Pay';
      case PlatformPaymentType.samsungPay:
        return 'Samsung Pay';
      case PlatformPaymentType.huaweiPay:
        return 'Huawei Pay';
      case PlatformPaymentType.miPay:
        return 'Mi Pay';
      case PlatformPaymentType.paypalSDK:
        return 'PayPal';
      case PlatformPaymentType.stripeSdk:
        return 'Stripe';
      case PlatformPaymentType.amazonPay:
        return 'Amazon Pay';
    }
  }

  /// Indicates whether availability depends on the user's region.
  bool get isRegionDependent {
    switch (this) {
      case PlatformPaymentType.applePay:
      case PlatformPaymentType.googlePay:
      case PlatformPaymentType.samsungPay:
      case PlatformPaymentType.huaweiPay:
      case PlatformPaymentType.miPay:
      case PlatformPaymentType.amazonPay:
        return true;
      case PlatformPaymentType.paypalSDK:
      case PlatformPaymentType.stripeSdk:
        return false;
    }
  }

  /// Indicates whether the provider needs specific device capabilities.
  bool get requiresDeviceCapability {
    switch (this) {
      case PlatformPaymentType.applePay:
      case PlatformPaymentType.googlePay:
      case PlatformPaymentType.samsungPay:
      case PlatformPaymentType.huaweiPay:
      case PlatformPaymentType.miPay:
        return true;
      case PlatformPaymentType.paypalSDK:
      case PlatformPaymentType.stripeSdk:
      case PlatformPaymentType.amazonPay:
        return false;
    }
  }
}

/// Payment flow failures (SDK config, auth, network, user cancel, etc.).
@immutable
class PlatformPaymentException extends BaseException {
  /// Creates a payment exception tied to the specific provider [type].
  PlatformPaymentException({
    required this.type,
    this.errorCode,
    this.transactionId,
    this.amount,
    this.currency,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity,
    super.isReportable,
  }) : super(
          userMessage: userMessage ?? '${type.displayName} payment failed.',
          devMessage:
              devMessage ?? '${type.displayName} payment failed: $errorCode',
          metadata: {
            'paymentType': type.name,
            if (errorCode != null) 'errorCode': errorCode,
            if (transactionId != null) 'transactionId': transactionId,
            if (amount != null) 'amount': amount,
            if (currency != null) 'currency': currency,
            ...metadata,
          },
        );
  // Convenience factories:

  /// Convenience constructor for user-cancelled payment attempts.
  factory PlatformPaymentException.cancelled({
    required PlatformPaymentType type,
    String? transactionId,
    Object? cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'payment_cancelled',
      userMessage: 'Payment was cancelled.',
      devMessage: '${type.displayName} payment cancelled by user.',
      transactionId: transactionId,
      cause: cause,
      stack: stack,
      isReportable: false,
      metadata: metadata,
    );
  }

  /// Convenience constructor when the payment method is currently unavailable.
  factory PlatformPaymentException.notAvailable({
    required PlatformPaymentType type,
    Object? cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
  }) {
    final msg = type.requiresDeviceCapability
        ? '${type.displayName} is not available on this device.'
        : '${type.displayName} is currently unavailable.';
    return PlatformPaymentException(
      type: type,
      errorCode: 'payment_not_available',
      userMessage: msg,
      devMessage: '${type.displayName} payment method not available.',
      cause: cause,
      stack: stack,
      metadata: metadata,
    );
  }

  /// Convenience constructor when the payment method is unsupported.
  factory PlatformPaymentException.notSupported({
    required PlatformPaymentType type,
    Object? cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
  }) {
    final msg = type.isRegionDependent
        ? '${type.displayName} is not supported in your region.'
        : '${type.displayName} is not supported.';
    return PlatformPaymentException(
      type: type,
      errorCode: 'payment_not_supported',
      userMessage: msg,
      devMessage: '${type.displayName} payment method not supported.',
      cause: cause,
      stack: stack,
      metadata: metadata,
    );
  }

  /// Convenience constructor for configuration issues (keys, merchant IDs, etc.).
  factory PlatformPaymentException.invalidConfiguration({
    required PlatformPaymentType type,
    String? details,
    Object? cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'invalid_configuration',
      userMessage: 'Payment system is not properly configured.',
      devMessage:
          'Invalid ${type.displayName} configuration${details != null ? ': $details' : ''}.',
      cause: cause,
      stack: stack,
      metadata: {
        if (details != null) 'configurationDetails': details,
        ...metadata,
      },
    );
  }

  /// Convenience constructor for insufficient funds errors.
  factory PlatformPaymentException.insufficientFunds({
    required PlatformPaymentType type,
    String? transactionId,
    double? amount,
    String? currency,
    Object? cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'insufficient_funds',
      userMessage: 'Insufficient funds to complete the payment.',
      devMessage: 'Insufficient funds for ${type.displayName} payment.',
      transactionId: transactionId,
      amount: amount,
      currency: currency,
      cause: cause,
      stack: stack,
      metadata: metadata,
    );
  }

  /// Convenience constructor for payment authentication failures.
  factory PlatformPaymentException.authenticationFailed({
    required PlatformPaymentType type,
    String? transactionId,
    String? details,
    Object? cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'authentication_failed',
      userMessage: 'Payment authentication failed.',
      devMessage:
          '${type.displayName} authentication failed${details != null ? ': $details' : ''}.',
      transactionId: transactionId,
      cause: cause,
      stack: stack,
      metadata: {
        if (details != null) 'authDetails': details,
        ...metadata,
      },
    );
  }

  /// Convenience constructor for transient network errors.
  factory PlatformPaymentException.networkError({
    required PlatformPaymentType type,
    String? transactionId,
    Object? cause,
    StackTrace? stack,
    Map<String, dynamic> metadata = const {},
  }) {
    return PlatformPaymentException(
      type: type,
      errorCode: 'network_error',
      userMessage: 'Network error occurred during payment.',
      devMessage: 'Network error during ${type.displayName} payment.',
      transactionId: transactionId,
      cause: cause,
      stack: stack,
      metadata: metadata,
    );
  }

  /// Payment provider that surfaced the error.
  final PlatformPaymentType type;

  /// Provider-specific error code, if supplied.
  final String? errorCode;

  /// Transaction identifier associated with the failure.
  final String? transactionId;

  /// Monetary amount involved in the transaction.
  final double? amount;

  /// ISO currency code for the transaction.
  final String? currency;
}
