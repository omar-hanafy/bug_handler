// helpers.dart
import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/api_exception.dart';
import 'package:flutter_helper_utils/flutter_helper_utils.dart';

class HttpStatusCodeInfo {
  HttpStatusCodeInfo(this.statusCode)
    : isSuccess = statusCode.isSuccessCode,
      isOk = statusCode.isOkCode,
      isCreated = statusCode.isCreatedCode,
      isAccepted = statusCode.isAcceptedCode,
      isNoContent = statusCode.isNoContentCode,
      isClientError = statusCode.isClientErrorCode,
      isServerError = statusCode.isServerErrorCode,
      isRedirectionCode = statusCode.isRedirectionCode,
      isTemporaryRedirect = statusCode.isTemporaryRedirect,
      isPermanentRedirect = statusCode.isPermanentRedirect,
      isAuthenticationError = statusCode.isAuthenticationError,
      isValidationError = statusCode.isValidationError,
      isRateLimitError = statusCode.isRateLimitError,
      isTimeoutError = statusCode.isTimeoutError,
      isConflictError = statusCode.isConflictError,
      isNotFoundError = statusCode.isNotFoundError,
      isRetryableError = statusCode.isRetryableError,
      statusCodeRetryDelay = statusCode.statusCodeRetryDelay,
      statusMessages = statusCode.toHttpStatusMessage,
      statusUserMessage = statusCode.toHttpStatusUserMessage,
      statusDevMessage = statusCode.toHttpStatusDevMessage,
      errorSeverity = _determineSeverity(statusCode);

  /// Determines error severity based on status code
  static ErrorSeverity _determineSeverity(int statusCode) {
    if (statusCode >= 500) return ErrorSeverity.error;
    if (statusCode == 401 || statusCode == 403) return ErrorSeverity.warning;
    if (statusCode == 404) return ErrorSeverity.info;
    if (statusCode == 429) return ErrorSeverity.warning;
    return ErrorSeverity.error;
  }

  final int statusCode;

  /// Checks if the status code represents a successful response (2xx)
  final bool isSuccess;

  /// Checks if the status code specifically represents OK (200)
  final bool isOk;

  /// Checks if the status code specifically represents Created (201)
  final bool isCreated;

  /// Checks if the status code specifically represents Accepted (202)
  final bool isAccepted;

  /// Checks if the status code specifically represents No Content (204)
  final bool isNoContent;

  /// Checks if the status code represents a client error (4xx)
  final bool isClientError;

  /// Checks if the status code represents a server error (5xx)
  final bool isServerError;

  /// Checks if the status code represents a redirection (3xx)
  final bool isRedirectionCode;

  /// Checks if the status code represents a temporary redirection
  final bool isTemporaryRedirect;

  /// Checks if the status code represents a permanent redirection
  final bool isPermanentRedirect;

  /// Checks if the status code represents an authentication error
  final bool isAuthenticationError;

  /// Checks if the status code represents a validation error
  final bool isValidationError;

  /// Checks if the status code represents a rate limit error
  final bool isRateLimitError;

  /// Checks if the status code represents a timeout error
  final bool isTimeoutError;

  /// Checks if the status code represents a conflict
  final bool isConflictError;

  /// Checks if the status code represents a not found error
  final bool isNotFoundError;

  /// Checks if the request should be retried based on the status code
  final bool isRetryableError;

  /// Gets suggested retry delay as a Duration based on status code
  final Duration statusCodeRetryDelay;

  /// Returns the HTTP status message associated with the number.
  /// If the status code is not found, it returns "Not Found".
  final String statusMessages;

  /// Returns the user-friendly HTTP status message associated with the number.
  /// If the status code is not found, it returns "Not Found".
  final String statusUserMessage;

  /// Returns the developer-friendly HTTP status message associated with the number.
  /// If the status code is not found, it returns "Not Found".
  final String statusDevMessage;

  /// Determines error severity based on status code
  final ErrorSeverity errorSeverity;

  Map<String, dynamic> toMap() => {
    'statusCode': statusCode,
    'isSuccess': isSuccess,
    'isOk': isOk,
    'isCreated': isCreated,
    'isAccepted': isAccepted,
    'isNoContent': isNoContent,
    'isClientError': isClientError,
    'isServerError': isServerError,
    'isRedirectionCode': isRedirectionCode,
    'isTemporaryRedirect': isTemporaryRedirect,
    'isPermanentRedirect': isPermanentRedirect,
    'isAuthenticationError': isAuthenticationError,
    'isValidationError': isValidationError,
    'isRateLimitError': isRateLimitError,
    'isTimeoutError': isTimeoutError,
    'isConflictError': isConflictError,
    'isNotFoundError': isNotFoundError,
    'isRetryableError': isRetryableError,
    'statusCodeRetryDelay': statusCodeRetryDelay.inMilliseconds,
    'statusMessages': statusMessages,
    'statusUserMessage': statusUserMessage,
    'statusDevMessage': statusDevMessage,
    'errorSeverity': errorSeverity.name,
  };
}

/// List of field names that should be considered sensitive and masked/encrypted
/// in logs, error reports, and debug output
const sensitiveFields = [
  // Authentication & Authorization
  'authorization',
  'auth',
  'authenticate',
  'bearer',
  'basic_auth',
  'api_key',
  'apikey',
  'api-key',
  'client_secret',
  'client-secret',
  'secret',
  'private_key',
  'privatekey',
  'private-key',
  'public_key',
  'publickey',
  'public-key',

  // Tokens
  'token',
  'access_token',
  'accesstoken',
  'access-token',
  'refresh_token',
  'refreshtoken',
  'refresh-token',
  'id_token',
  'idtoken',
  'id-token',
  'jwt',
  'session_token',
  'sessiontoken',
  'session-token',

  // Passwords
  'password',
  'passwd',
  'pass',
  'pwd',
  'secret_key',
  'secretkey',
  'secret-key',
  'passphrase',

  // Financial Information
  'credit_card',
  'creditcard',
  'credit-card',
  'card_number',
  'cardnumber',
  'card-number',
  'cvv',
  'cvc',
  'ccv',
  'security_code',
  'securitycode',
  'security-code',
  'expiry',
  'expiration',
  'bank_account',
  'bankaccount',
  'bank-account',
  'routing_number',
  'routingnumber',
  'routing-number',
  'account_number',
  'accountnumber',
  'account-number',
  'iban',
  'swift',
  'bic',

  // Personal Identifiable Information (PII)
  'ssn',
  'social_security',
  'socialsecurity',
  'social-security',
  'tax_id',
  'taxid',
  'tax-id',
  'passport',
  'passport_number',
  'passportnumber',
  'passport-number',
  'drivers_license',
  'driverslicense',
  'drivers-license',
  'license_number',
  'licensenumber',
  'license-number',

  // Healthcare Information
  'medical_record',
  'medicalrecord',
  'medical-record',
  'health_id',
  'healthid',
  'health-id',
  'insurance_id',
  'insuranceid',
  'insurance-id',

  // Biometric Data
  'fingerprint',
  'facial_data',
  'facialdata',
  'facial-data',
  'biometric',
  'retina_scan',
  'retinascan',
  'retina-scan',

  // Contact Information
  'phone',
  'phone_number',
  'phonenumber',
  'phone-number',
  'mobile',
  'mobile_number',
  'mobilenumber',
  'mobile-number',

  // Recovery Information
  'security_question',
  'securityquestion',
  'security-question',
  'security_answer',
  'securityanswer',
  'security-answer',
  'recovery_code',
  'recoverycode',
  'recovery-code',

  // Device & Location
  'device_id',
  'deviceid',
  'device-id',
  'imei',
  'mac_address',
  'macaddress',
  'mac-address',
  'geolocation',
  'coordinates',
  'location',

  // Generic Sensitive Terms
  'private',
  'sensitive',
  'confidential',
  'restricted',
  'hidden',
  'protected',
  'secure',
  'encrypted',
];

/// Function to check if a field name contains sensitive information
bool isSensitiveField(String fieldName) {
  final normalizedField = fieldName.toLowerCase().trim();
  return sensitiveFields.any(
    (field) =>
        normalizedField == field ||
        normalizedField.contains(field) ||
        normalizedField.startsWith(field) ||
        normalizedField.endsWith(field),
  );
}

/// Function to mask sensitive value while preserving some structure
String maskSensitiveValue(String value) {
  if (value.isEmpty) return '';
  if (value.length <= 4) return '*' * value.length;

  // Preserve first and last character, mask the rest
  return '${value[0]}${'*' * (value.length - 2)}${value[value.length - 1]}';
}

extension BugReportSystemExtension on Object? {
  bool get isUnauthorizedError {
    final e = this;
    return e is ApiException && e.httpStatusInfo.isAuthenticationError;
  }
}
