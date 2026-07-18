# bug_handler API quick reference (1.0.0-dev.5+)

Verified against package source. When in doubt, read the installed package source in
`~/.pub-cache/hosted/pub.dev/bug_handler-<version>/lib/` instead of guessing.

## Import map (critical, commonly gotten wrong)

`package:bug_handler/bug_handler.dart` exports: core (client, config, event, guard,
outbox, result), all 13 exception files, context providers, privacy
(sanitizers, filters), reporters (reporter, composite, console, share).

It does NOT export these; they need their own imports:

```dart
import 'package:bug_handler/flutter/bindings.dart';        // BugReportBindings
import 'package:bug_handler/flutter/error_boundary.dart';  // ErrorBoundary
import 'package:bug_handler/helpers.dart';                 // HttpStatusCodeInfo, sensitiveFields, isSensitiveField, maskSensitiveValue
```

`ApiException` requires `HttpStatusCodeInfo`, so constructing one always needs the
`helpers.dart` import. The empty files `reporters/adapters/sentry.dart` and
`reporters/adapters/crashlytics.dart` are placeholders with no code; never import them.

## BugReportClient (core/client.dart)

Singleton: `BugReportClient.instance`.

```dart
bool get isInitialized;
Future<void> initialize(ClientConfig config);       // second call is silently ignored; no reset API
void addContextProvider(ContextProvider p);          // runtime providers (e.g., user after login)
void removeContextProvider(ContextProvider p);
void clearContextProviders();
void addBreadcrumb(String message, {Map<String, dynamic> data = const {}, DateTime? timestamp});
void clearBreadcrumbs();
Future<ReportEvent> createEvent(BaseException e, {Map<String, dynamic> additionalContext = const {}, bool manual = false, bool handled = true});
Future<bool> report(ReportEvent event);              // applies policy; may enqueue to outbox
Future<ReportEvent> capture(BaseException e, {...}); // createEvent + report; THROWS StateError if uninitialized
Future<void> captureSafely(BaseException e, {...});  // never throws; no-op before initialize (since 1.0.0-dev.5)
Future<void> flush();                                // drain outbox through current pipeline
```

Version note: `captureSafely` exists only since 1.0.0-dev.5. On 1.0.0-dev.1..4,
`guard` used `capture` and could throw from the reporting path; recommend upgrading
to >= 1.0.0-dev.5 before relying on the never-throw guarantee.

## ClientConfig and Policy (core/config.dart)

```dart
ClientConfig({
  required String environment,                 // free-form label: 'dev' | 'staging' | 'prod' | AppMode.name
  List<ContextProvider> baseProviders = const [],
  List<ContextProvider> additionalProviders = const [],
  List<Sanitizer> sanitizers = const [],
  List<EventTransform> transforms = const [],  // ReportEvent Function(ReportEvent)
  Policy policy = const Policy(),
  List<Reporter> reporters = const [],
  int maxBreadcrumbs = 100,
})

Policy({
  Severity minSeverity = Severity.error,
  bool reportHandled = true,
  Set<String> environments = const {},         // empty = allow all
  double sampling = 1.0,
  RateLimit rateLimit = const RateLimit(10, Duration(minutes: 1)),
  DedupeStrategy dedupe = const DedupeStrategy.windowed(), // default 60s window
})
```

`Severity` order: `critical(0) < error(1) < warning(2) < info(3)` by index. An
event is dropped when `event.exception.severity.index > minSeverity.index`, so
`minSeverity: Severity.error` drops warnings and info; `Severity.warning` keeps
critical+error+warning. `typedef ErrorSeverity = Severity` exists for legacy code.

`BaseException.isReportable` is NOT consulted anywhere in the current pipeline.
See policy-and-delivery.md for the full gate order and this trap.

## Guards and Result (core/guard.dart, core/result.dart)

```dart
Future<Result<T, BaseException>> guard<T>(Future<T> Function() action, {
  String? source,                       // stable label 'ClassName.method'; feeds fingerprints
  FutureOr<void> Function(T)? onSuccess,
  FutureOr<void> Function(BaseException)? onError,
  bool manual = false,
  Map<String, dynamic> additionalContext = const {},
});
Result<T, BaseException> guardSync<T>(T Function() compute, {same params});
T parser<T>(T Function() build, {required Object? data}); // throws ParsingException on failure
BaseException normalizeError(Object error, StackTrace stack, {String? source, Severity defaultSeverity = Severity.error});
```

- `guard` awaits `captureSafely`; `guardSync` fire-and-forgets it (`unawaited`).
- Both report with `handled: true`. `BugReportBindings` reports uncaught errors with `handled: false`.
- Normalization order: `BaseException` passthrough -> `PlatformException` ->
  `PlatformOperationException.fromPlatformException(operation: source ?? 'unknown_operation')`
  -> `FormatException` -> `ParsingException` -> anything else -> `UnexpectedException`
  with `metadata['source']` set when provided.

`Result<T, E extends BaseException>` is sealed: `Ok(value)` / `Err(error)`.
Members: `isOk`, `isErr`, `match(ok:, err:)`, `unwrap()`, `unwrapOr(fallback)`,
`unwrapOrElse(f)`, `map`, `mapErr`, `andThen`, `andThenAsync`, extension `mapAsync`.
Dart 3 pattern matching works: `switch (res) { case Ok(:final value): ...; case Err(:final error): ...; }`.

## ReportEvent (core/event.dart)

Immutable. Fields: `id`, `exception`, `context`, `timestamp`, `fingerprints`,
`breadcrumbs`, `attachments`, `handled`, plus an embedded pre-sanitized payload.
`toMap()`/`toJson()` return the SANITIZED payload when present; custom reporters
must read `event.toMap()`, never rebuild payloads from `event.context` (that would
bypass sanitization). `ReportEvent.fromMap/fromJson` rehydrate outbox items using
`SerializedException` (original subtype is not preserved across outbox replay).

Fingerprints computed by the client: `[runtimeType, 'src:<metadata.source>',
'frame:<top stack line>', 'msg:<hash(devMessage)>']` (src/frame included only when
available).

## Reporters (reporters/)

```dart
abstract class Reporter {
  const Reporter();
  Future<bool> send(ReportEvent event);                  // required; true == delivered
  Future<bool> share(ReportEvent event) async => false;  // optional user-initiated share
  @protected Future<File> generateFile(ReportEvent event, {String? fileName, Directory? directory});
  @protected String defaultFileName(ReportEvent event);
}
```

- `CompositeReporter(reporters)`: fan-out; success if ANY reporter returns true;
  individual throws are swallowed.
- `ConsoleReporter({enabled = true, prettyJson = false, maxContextKeysPreview = 12, maxMessageLength = 240})`:
  debugPrint summary; returns true when enabled.
- `ShareReporter({subjectPrefix = 'Bug Report', textBuilder, fileNameBuilder})`:
  `send()` delegates to `share()` (platform share sheet via share_plus). A completed
  share counts as delivery success for the whole pipeline.

## Context providers (context/)

```dart
abstract class ContextProvider {                 // const-able, @immutable
  String get name;                               // context key
  bool get manualReportOnly => false;            // true = only for manual reports
  FutureOr<Map<String, dynamic>> getData();      // must never throw; return {} on failure
  bool validateData(Map<String, dynamic> data) => data.isNotEmpty;
}
mixin CachedContextProvider on ContextProvider { // TTL cache + in-flight dedupe
  Duration get cacheDuration => const Duration(minutes: 5);
  @protected FutureOr<Map<String, dynamic>> collect();   // override this, not getData
  void clearCache();
}
```

Built-ins: `AppContextProvider` (name 'app', cache 2 min; package info, network
interfaces, battery; DI params `packageInfo`, `battery`, `connectivity`, `additional`),
`DeviceContextProvider` (name 'device', cache 1h; device_info_plus per platform; DI
`deviceInfo`), `NetworkContextProvider` (name 'network', cache 1 min; interfaces +
optional wifi ssid/bssid/ip; DI `connectivity`, `info`), `UIContextProvider(context)`
(name 'ui', manualReportOnly = true, needs BuildContext), `UserContextProvider`
(name 'user'; `id`, `email`, `role`, `tenantId`, `traits`, `manualOnly` flag).

## Sanitizers and filters (privacy/)

Pipeline: `event.toMap()` -> each `Sanitizer.sanitize(map)` in ClientConfig order.

- `DefaultSanitizer({matcher, fieldMask, contentMask, enableContentBasedDetection = true})`
  masks by key (auth/passwords/financial/PII/device keys, case- and
  underscore/dash-insensitive) and by content (JWTs, `AKIA|ASIA` AWS key ids,
  bearer strings, ANY `[A-Za-z0-9-_.]{24,}` token-like string, and any string whose
  digit count is 13..19 -> card masking). Extend keys via
  `SensitiveFieldMatcher(extraKeys: {...})`; tune `MaskingStrategy(keepStart:, keepEnd:)`.
- `RegexValueSanitizer({RegExp: replacement})` global string rewrites.
- `MaxDepthSanitizer({maxDepth = 8})` -> '<redacted:depth>'.
- `TruncatingSanitizer({maxString = 1000, maxList = 200, maxMapEntries = 200})`.
- `SizeBudgetSanitizer({required maxBytes, pinnedTopLevelKeys = {'exception','timestamp','fingerprints'}})`
  drops largest non-pinned top-level entries first; will redact pinned keys as a
  last resort.
- `FilterSanitizer(DataFilter)` bridges `AllowListFilter(paths, {keepEmptyParents})` /
  `DenyListFilter(paths)` / `FilterChain([...])`.
- Path syntax: `a.b.c` exact, `a.*.c` one segment, `a.**.c` any depth, `**.token`
  key anywhere. Filters recurse into lists of maps.

## Flutter wiring (flutter/)

```dart
BugReportBindings.runAppWithReporting({
  required Widget Function() app,
  required ClientConfig config,
  bool captureFrameworkErrors = true,
  bool capturePlatformDispatcherErrors = true,
  bool attachIsolateErrorListener = true,
  bool useDefaultFlutterErrorPresentation = true,
});
```

Wires FlutterError.onError, PlatformDispatcher.onError, runZonedGuarded, isolate
listener; reports uncaught errors via `captureSafely(handled: false)`. Apps may
instead hand-roll this wiring and call `BugReportClient.instance.initialize` +
`flush()` after runApp (both styles are used in production).

`ErrorBoundary({required child, fallbackBuilder, onException, onRetry, showDetails})`
with `ErrorBoundary.of(context)` state helpers: `guardFuture`, `guardCallback`,
`guardAsyncCallback`, `guardStream`, `show(BaseException)`. Boundary reports with
`manual: true`. Default fallback offers Retry + Report buttons.

## HttpStatusCodeInfo (helpers.dart)

`HttpStatusCodeInfo(statusCode)` exposes `isSuccess/isClientError/isServerError/
isAuthenticationError/isValidationError/isRateLimitError/isTimeoutError/
isConflictError/isNotFoundError/isRetryableError`, `statusCodeRetryDelay`,
`statusUserMessage`, `statusDevMessage`, and `errorSeverity` (5xx -> error,
401/403 -> warning, 404 -> info, 429 -> warning, else error). `toMap()` feeds
`ApiException.metadata['http']`.

## Outbox (core/outbox.dart)

Files `<id>.json` under `Documents/bug_report_outbox` (path_provider). Enqueued
ONLY when delivery fails or rate limit trips. `flush()` sends pending in filename
order and deletes on success. Corrupt files are deleted on read. Platforms without
path_provider documents dirs (plain unit tests) make outbox writes throw; the
client's `captureSafely` swallows that.
