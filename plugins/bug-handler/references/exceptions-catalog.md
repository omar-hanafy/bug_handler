# bug_handler exceptions catalog

Every type extends `BaseException` (immutable, Equatable, `implements Exception`).
Base fields: `userMessage` (end-user safe), `devMessage` (logs/tools), `cause`,
`stack` (defaults to `StackTrace.current`), `metadata` (unmodifiable copy),
`severity` (default `Severity.error`), `isReportable` (default `true`).

Equality (`props`) covers runtimeType, messages, severity, isReportable, metadata,
and `cause.runtimeType`; stack is excluded on purpose.

IMPORTANT: `isReportable` is metadata only in 1.0.0-dev.x. The client pipeline
never checks it. If a type below says `isReportable: false`, that is a hint for
YOUR reporters/policies, not an automatic drop. Filter in a custom Reporter or
rely on severity gating when you need the drop behavior.

## Which type to throw where

| Situation | Type | Defaults set by the type |
|---|---|---|
| HTTP / API failure | `ApiException(httpStatusInfo: HttpStatusCodeInfo(code), endpoint:, method:, requestHeaders:, requestBody:, responseHeaders:, responseBody:)` | severity from `httpStatusInfo.errorSeverity`; devMessage `HTTP <code> <METHOD> <endpoint>`; metadata under `metadata['http']` |
| Auth / identity provider | `AuthException(userMessage:, errorCode:, provider:)` | metadata `errorCode`, `provider` |
| Session/token lifecycle | `TokenException(devMessage:, ...)` extends AuthException | userMessage 'Your session has expired. Please sign in again.'; severity error |
| Data transform / IO | `DataProcessingException(userMessage:, devMessage:, data:, operation:)` | metadata `operation`, `rawData` |
| JSON/model parsing | `ParsingException(rawData:, targetType:)` extends DataProcessingException | severity error; operation 'parsing'; userMessage 'Unable to process data.' Prefer throwing via `parser(() => Model.fromJson(json), data: json)` |
| Flutter framework error | `FlutterErrorException(details)` | wraps FlutterErrorDetails; severity error; rich `metadata['flutter']`; used by BugReportBindings |
| Bootstrap failure | `InitializationException(component:)` | severity ALWAYS critical (cannot override) |
| Used-before-init | `ComponentNotInitializedException(component:)` | severity critical |
| Navigation/routing | `NavigationException(route:, operation:, arguments:)` | severity warning, isReportable false |
| Route missing | `RouteNotFoundException` / bad args `InvalidRouteArgumentsException` | severity warning, isReportable false |
| Permission denied | `PermissionException(permission:, status: PermissionStatus.x)` | severity: permanentlyDenied/restricted -> error; denied/limited/provisional -> warning; granted -> info. isReportable false. Localized default userMessage per status |
| Platform channel / OS | `PlatformOperationException(operation:, userMessage:, devMessage:, code:, details:)` or `.fromPlatformException(e, operation:)` | factory derives severity+userMessage from code substrings ('permission'/'timeout'/'invalid' -> warning, 'unavailable' -> error); getters `isTimeout`, `isPermissionError` |
| Media flows | `MediaException(type: MediaOperationType.x, mediaType:)` extends PlatformOperationException | operation 'media_<type>'; permission/format/size -> warning, upload/download/picker/processing -> error |
| Payments | `PlatformPaymentException(type: PlatformPaymentType.x, errorCode:, transactionId:, amount:, currency:)` + factories `.cancelled` (isReportable false) `.notAvailable` | metadata paymentType/errorCode/transactionId/amount/currency |
| Storage | `StorageException(userMessage:, devMessage:, operation:, key:, storageType:)` | metadata operation/key/storageType |
| Cache | `CacheException(key:, operation:)` | severity error, isReportable true, storageType 'cache' |
| Keychain/keystore | `SecureStorageException(key:, operation:)` | severity error, isReportable true, storageType 'secure_storage' |
| User input invalid | `ValidationException(userMessage:, validationErrors: {...})` | severity warning, isReportable false, metadata `validationErrors` |
| Unknown fallback | `UnexpectedException(userMessage:, devMessage:, cause:, stack:)` | fills metadata `errorType`, `originalError`; used by `normalizeError` and bindings |

Enums shipped with the package: `Severity {critical,error,warning,info}` (alias
`ErrorSeverity`), `PermissionStatus {denied, permanentlyDenied, restricted,
limited, provisional, granted}`, `MediaOperationType {upload, download, picker,
processing, permission, format, size}`, `PlatformPaymentType {applePay, googlePay,
samsungPay, huaweiPay, miPay, paypalSDK, stripeSdk, amazonPay}`.

## App-specific exception subclassing pattern

Apps are expected to subclass for their domain. The canonical example is an
API exception bound to the app's backend semantics:

```dart
import 'package:bug_handler/bug_handler.dart';
import 'package:bug_handler/helpers.dart'; // HttpStatusCodeInfo lives here

class AppApiException extends ApiException {
  AppApiException({
    required HttpStatusCodeInfo info,
    String? endpoint,
    String? method,
    Object? responseBody,
    Map<String, dynamic> responseHeaders = const {},
  }) : super(
          httpStatusInfo: info,
          endpoint: endpoint,
          method: method,
          responseHeaders: responseHeaders,
          responseBody: responseBody,
          userMessage: _userFacing(info),
          severity: _severityOverride(info),
        );

  factory AppApiException.fromResponse({
    required int statusCode,
    required String endpoint,
    required String method,
    Object? responseBody,
    Map<String, dynamic> responseHeaders = const {},
  }) =>
      AppApiException(
        info: HttpStatusCodeInfo(statusCode),
        endpoint: endpoint,
        method: method,
        responseBody: responseBody,
        responseHeaders: responseHeaders,
      );

  static String _userFacing(HttpStatusCodeInfo i) {
    if (i.isValidationError) return 'Please check your input and try again.';
    if (i.isRateLimitError) return 'Too many attempts. Try again shortly.';
    if (i.isTimeoutError) return 'Network timeout. Check your connection and retry.';
    return i.statusUserMessage;
  }

  static Severity _severityOverride(HttpStatusCodeInfo i) =>
      i.isNotFoundError ? Severity.info : i.errorSeverity;
}
```

Guidance for subclasses:
- Always give `userMessage` a RESOLVED, human-readable string. Do not store
  localization keys in `userMessage` (a real production bug: raw keys rendered in
  UI). If you localize, resolve at construction or at render time deliberately.
- Put structured facts in `metadata` (they survive serialization and reach
  reporters); put searchable identity in the type + `metadata['source']`.
- Set `severity` deliberately: it is the primary delivery gate.
- Setting `isReportable` documents intent but does not change delivery by itself.
