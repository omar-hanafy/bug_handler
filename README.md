# Bug Handler

A resilient, privacy‑first error reporting toolkit for Dart & Flutter applications.

It gives you:

* A central client to create, sanitize, deduplicate, rate‑limit, and send error reports.
* Built‑in **context providers** (app, device, network, UI, user) with caching and opt‑in heavy data.
* A flexible **sanitization pipeline** (masking by key and content, regex rewrites, depth/size pruning, allow/deny filters).
* **Policy controls** (severity gating, environment allow‑list, sampling, rate‑limit, dedupe window).
* **Outbox** persistence for offline scenarios and delivery retries.
* A composable **reporter** pipeline (console logging, share sheet; adapters stubs for Sentry/Crashlytics).
* Developer‑friendly **guard** helpers, a **Result** type, and a **Flutter ErrorBoundary** widget.
* A typed **exception** hierarchy that standardizes error shape and severity across domains.

> Package entrypoint: `package:bug_handler/bug_handler.dart` re‑exports all public APIs.

---

## Table of contents

1. [Installation](#installation)
2. [Quick start](#quick-start)
3. [Core concepts](#core-concepts)

   * [BugReportClient](#bugreportclient)
   * [ClientConfig & Policy](#clientconfig--policy)
   * [ReportEvent](#reportevent)
   * [Context providers](#context-providers)
   * [Sanitizers & Filters](#sanitizers--filters)
   * [Reporters](#reporters)
   * [Outbox](#outbox)
   * [Breadcrumbs](#breadcrumbs)
4. [Flutter wiring](#flutter-wiring)

   * [Global bindings](#global-bindings)
   * [ErrorBoundary widget](#errorboundary-widget)
5. [Guard helpers & Result](#guard-helpers--result)
6. [Exceptions overview](#exceptions-overview)
7. [Transform hooks](#transform-hooks)
8. [Extending](#extending)
9. [Testing & tips](#testing--tips)
10. [Troubleshooting](#troubleshooting)
11. [FAQ](#faq)
12. [License](#license)

---

## Installation

Add the package to yaml:

```yaml
dependencies:
  bug_handler: ^<latest>
```

Then import:

```dart
import 'package:bug_handler/bug_handler.dart';
```

---

## Quick start

Initialize once during app bootstrap and run your app under the provided bindings:

```dart
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:bug_handler/bug_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await BugReportBindings.runAppWithReporting(
    app: () => const MyApp(),
    config: ClientConfig(
      environment: kReleaseMode ? 'prod' : 'dev',
      baseProviders: [
        AppContextProvider(),
        DeviceContextProvider(),
      ],
      additionalProviders: [
        NetworkContextProvider(),
        // Add user/session provider at login time if desired (see below).
      ],
      sanitizers: [
        DefaultSanitizer(),
        MaxDepthSanitizer(maxDepth: 8),
        TruncatingSanitizer(maxString: 2_000, maxList: 200, maxMapEntries: 200),
        SizeBudgetSanitizer(maxBytes: 60 * 1024), // ~60 KB cap
      ],
      policy: Policy(
        minSeverity: Severity.error,
        reportHandled: true,
        environments: {'prod', 'staging', 'dev'},
        sampling: 1.0,
        rateLimit: RateLimit(20, Duration(minutes: 1)),
        dedupe: DedupeStrategy.windowed(Duration(seconds: 30)),
      ),
      reporters: [
        ConsoleReporter(prettyJson: false),
        ShareReporter(), // enables “Report” UX and manual sharing
      ],
      maxBreadcrumbs: 100,
    ),
  );
}
```

Capture and report an exception anywhere:

```dart
await BugReportClient.instance.capture(
  DataProcessingException(
    userMessage: 'Could not load profile.',
    devMessage: 'Failed to parse UserDto from /me',
    data: responseBody,
    operation: 'parsing',
  ),
);
```

Add runtime user context (masking is handled by your sanitizers):

```dart
BugReportClient.instance.addContextProvider(
  UserContextProvider(
    id: currentUser.id,
    email: currentUser.email,
    role: currentUser.role,
    manualOnly: true, // only in user-initiated reports
  ),
);
```

---

## Core concepts

### BugReportClient

The central orchestrator (`core/client.dart`):

* Singleton: `BugReportClient.instance`.
* `initialize(ClientConfig)` builds the reporter pipeline.
* Collects base + additional + runtime context providers, optionally including manual‑only providers for user‑initiated reports.
* Computes **fingerprints** (type, optional `metadata.source`, top stack frame, hashed dev message) used for dedupe/grouping.
* Applies transforms, then **sanitizers**, producing a **sanitized payload**.
* Enforces **policy**: severity gating, environment allow‑list, sampling, dedupe window, and a rate limiter.
* On send failure or rate‑limit, persists to **Outbox** for later flush.

Key methods:

```dart
Future<void> initialize(ClientConfig config);
void addContextProvider(ContextProvider p);
void removeContextProvider(ContextProvider p);
void clearContextProviders();

void addBreadcrumb(String message, { Map<String, dynamic> data = const {}, DateTime? timestamp });
void clearBreadcrumbs();

Future<ReportEvent> createEvent(BaseException e, { Map<String, dynamic> additionalContext = const {}, bool manual = false, bool handled = true });
Future<bool> report(ReportEvent e);
Future<ReportEvent> capture(BaseException e, { ... }); // create + report
Future<void> flush(); // send any Outbox items via current pipeline
```

### ClientConfig & Policy

Defined in `core/config.dart`.

```dart
class ClientConfig {
  final String environment;        // e.g., "dev", "staging", "prod"
  final List<ContextProvider> baseProviders;
  final List<ContextProvider> additionalProviders;
  final List<Sanitizer> sanitizers;
  final List<EventTransform> transforms; // ReportEvent -> ReportEvent
  final Policy policy;
  final List<Reporter> reporters;
  final int maxBreadcrumbs;
}
```

**Policy** controls pre‑send gating:

* `minSeverity`: drop events less severe than threshold.
* `reportHandled`: include caught errors, not only crashes.
* `environments`: required environment allow‑list (empty = all).
* `sampling`: probability [0..1] for dropping before runtime gates.
* `rateLimit`: `RateLimit(maxEvents, perWindow)`.
* `dedupe`: `DedupeStrategy.windowed(window)`; drop repeated fingerprints within window.

### ReportEvent

Canonical, serializable event (`core/event.dart`):

* Immutable with JSON serializer (`toJson`) and `fromJson`.
* Contains `exception` (typed), `context`, `breadcrumbs`, `fingerprints`, `attachments`, `handled` and `timestamp`.
* `withPayload` embeds a **pre‑sanitized** map so downstream reporters and the outbox store the safe version.

```dart
final event = ReportEvent(
  id: ReportEvent.generateId(),
  exception: e,
  context: {...},
  breadcrumbs: [...],
  fingerprints: ['...'],
  handled: true,
  timestamp: DateTime.now(),
);

// Convert to sanitized JSON for persistence/delivery:
final json = event.toJson();
```

### Context providers

Base contract in `context/provider.dart`:

* `ContextProvider` is immutable and returns a `FutureOr<Map<String, dynamic>> getData()`.
* `manualReportOnly` lets you include heavy or sensitive data **only** for user‑initiated reports.
* `CachedContextProvider` adds automatic caching with TTL and in‑flight deduplication. Providers never throw; they return `{}` on failure.

Built‑ins:

1. **AppContextProvider** (`built_in/app.dart`)

   * Package metadata: `appName`, `packageName`, `version`, `buildNumber`, `buildSignature`, `installerStore`.
   * Lightweight signals: network `interfaces` (from `connectivity_plus`), battery `level` (from `battery_plus`, `-1` if unavailable).
   * Cache: 2 minutes. Supports `additional()` hook.

2. **DeviceContextProvider** (`built_in/device.dart`)

   * Platform‑specific device info via `device_info_plus`.
   * Returns only helpful diagnostic fields and respects privacy by default.
   * Cache: 1 hour. On error, minimal `{ platform: ... }` fallback.

3. **NetworkContextProvider** (`built_in/network.dart`)

   * Normalized active `interfaces` via `connectivity_plus`.
   * If on Wi‑Fi, optionally collects `wifi` details (SSID/BSSID/IPs) via `network_info_plus` when accessible.
   * Cache: 1 minute.

4. **UIContextProvider** (`built_in/ui.dart`)

   * **manualReportOnly = true**.
   * Captures theme, color scheme, text theme sizes, platform, MediaQuery metrics (size, DPR, padding/insets, text scaling, orientation), locale, text direction, Navigator state, scheduler timing. Requires a `BuildContext`. Includes color serialization helpers via `flutter_helper_utils`.

5. **UserContextProvider** (`built_in/user.dart`)

   * Lightweight user/session data: `id`, `email`, `role`, `tenantId`, plus arbitrary `traits`.
   * Opt‑in `manualOnly` flag to include only on user‑initiated reports.

Add your own provider:

```dart
class CartContextProvider extends ContextProvider with CachedContextProvider {
  @override
  String get name => 'cart';

  @override
  Duration get cacheDuration => const Duration(seconds: 30);

  @override
  Future<Map<String, dynamic>> collect() async {
    // never throw; return {} on failure
    return {
      'items': cart.items.length,
      'total': cart.total,
    };
  }
}
```

Register it via config or at runtime with `BugReportClient.instance.addContextProvider(...)`.

### Sanitizers & Filters

Defined in `privacy/sanitizers.dart` and `privacy/filters.dart`.

Sanitizers run **before** payload storage and delivery:

* **DefaultSanitizer**: masks by **key** (e.g., `password`, `token`, `email`, `phone`, device/PII keys) and by **content** heuristics (JWTs, AWS Access Key IDs, bearer tokens, long token‑like strings, credit‑card‑like numbers). Uses `SensitiveFieldMatcher` + `MaskingStrategy`.
  Content heuristics keep structure but mask the inner parts.

* **RegexValueSanitizer**: global value rewrites via regex rules.

* **MaxDepthSanitizer**: prunes deep structures with a `<redacted:depth>` marker.

* **TruncatingSanitizer**: caps string length, list length, and map entry count.

* **SizeBudgetSanitizer**: keeps the final JSON under `maxBytes` by dropping large top‑level entries first (pins `exception`, `timestamp`, `fingerprints` by default) and marks with `<redacted:size>`.

* **FilterSanitizer** wraps a **DataFilter** (see below) to perform allow/deny operations.

Filters operate on arbitrary nested maps using dotted paths and wildcards:

* Path syntax examples:

  * `a.b.c` exact path
  * `a.*.c` single‑level wildcard
  * `a.**.c` match any depth from `a` to `c`
  * `**.token` any key named `token` anywhere

**AllowListFilter** keeps only specific paths; **DenyListFilter** removes matching paths.

Example configuration:

```dart
final allow = FilterSanitizer(
  AllowListFilter({
    'exception',                 // keep entire exception section
    'timestamp',
    'context.app',               // whole app context
    'context.device.model',      // only device.model
    'breadcrumbs',               // breadcrumbs list
  }),
);

final deny = FilterSanitizer(
  DenyListFilter({
    '**.token',                  // drop any token
    'context.user.email',        // drop user email
    'context.network.wifi',      // drop wifi details if you don’t need them
  }),
);

final config = ClientConfig(
  // ...
  sanitizers: [
    DefaultSanitizer(),
    deny,
    allow,
    MaxDepthSanitizer(maxDepth: 8),
    TruncatingSanitizer(maxString: 2000),
    SizeBudgetSanitizer(maxBytes: 60 * 1024),
  ],
);
```

> Sanitizers and filters never mutate inputs in place. They return new maps. Providers and the client never throw on sanitization errors.

### Reporters

Base contract in `reporters/reporter.dart`:

```dart
abstract class Reporter {
  const Reporter();
  Future<bool> send(ReportEvent event);           // required
  Future<bool> share(ReportEvent event) async => false; // optional
  // Helpers to generate a stable JSON file for sharing or persistence:
  @protected Future<File> generateFile(ReportEvent event, { String? fileName, Directory? directory });
  @protected String defaultFileName(ReportEvent event);
}
```

Built‑ins:

* **CompositeReporter** (`reporters/composite_reporter.dart`)
  Fans out to multiple reporters. A send is considered successful if **any** reporter succeeds. Swallows individual failures to keep the pipeline resilient.

* **ConsoleReporter** (`reporters/console_reporter.dart`)
  Logs a compact summary to debug console. Good for development.
  Options: `enabled`, `prettyJson` (log full payload), `maxContextKeysPreview`, `maxMessageLength`.

* **ShareReporter** (`reporters/share_reporter.dart`)
  Generates a `.json` file and invokes the platform share sheet via `share_plus`.
  Useful for user‑initiated reporting or when remote delivery isn’t available.
  Options: `subjectPrefix`, `textBuilder`, `fileNameBuilder`.
  `send()` delegates to `share()` so you can include it in any pipeline.

Adapters (stubs provided; implement in your app layer):

* `reporters/adapters/sentry.dart` — implement a `Reporter` that converts `ReportEvent` to Sentry payloads.
* `reporters/adapters/crashlytics.dart` — implement a `Reporter` that forwards to Crashlytics.

Example custom reporter:

```dart
class MyApiReporter extends Reporter {
  const MyApiReporter(this.client);
  final MyApiClient client;

  @override
  Future<bool> send(ReportEvent event) async {
    try {
      final ok = await client.postJson('/errors', event.toMap());
      return ok;
    } catch (_) {
      return false;
    }
  }
}
```

### Outbox

Durable queue in `core/outbox.dart`:

* Stores each sanitized event as `<id>.json` under `Documents/bug_report_outbox`.
* `enqueue(event)` is called automatically when send fails or when rate‑limited.
* `pending()` lists chronologically.
* `ack(id)` removes a file after successful delivery.
* `flushWith(pipeline)` iterates pending and sends via the current reporter pipeline.

You can trigger flush at strategic times (e.g., app resume, connectivity available):

```dart
await BugReportClient.instance.flush();
```

### Breadcrumbs

A ring buffer of recent diagnostic notes:

```dart
BugReportClient.instance.addBreadcrumb(
  'tapped_submit',
  data: {'screen': 'checkout', 'step': 2},
);
```

* Configurable size via `ClientConfig.maxBreadcrumbs` (default 100).
* Breadcrumbs are attached to every event created after recording them.
* Use `clearBreadcrumbs()` to reset between flows if helpful.

---

## Flutter wiring

### Global bindings

`flutter/bindings.dart` wires crash‑like sources:

* `FlutterError.onError` (build/layout/paint errors).
* `ui.PlatformDispatcher.onError` (unhandled errors crossing framework boundaries).
* `runZonedGuarded` to catch uncaught async errors.
* An isolate error listener to receive errors from other isolates.

Use:

```dart
await BugReportBindings.runAppWithReporting(
  app: () => const MyApp(),
  config: myConfig,
  captureFrameworkErrors: true,
  capturePlatformDispatcherErrors: true,
  attachIsolateErrorListener: true,
  useDefaultFlutterErrorPresentation: true,
);
```

Framework errors are wrapped as **FlutterErrorException** and sent through your pipeline. The bindings never throw; they fail closed.

### ErrorBoundary widget

A pragmatic, local error boundary that shows a fallback UI when operations in its subtree fail and are **reported through the boundary**.

```dart
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      onRetry: () => context.read<ProfileCubit>().refresh(),
      showDetails: !kReleaseMode,
      child: const _ProfileContent(),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent();

  @override
  Widget build(BuildContext context) {
    final boundary = ErrorBoundary.of(context);
    return ElevatedButton(
      onPressed: boundary.guardAsyncCallback(() async {
        await context.read<ProfileCubit>().load();
      }, source: 'ProfileScreen.load'),
      child: const Text('Load profile'),
    );
  }
}
```

Helpers on `ErrorBoundaryState`:

* `guardFuture`, `guardCallback`, `guardAsyncCallback`, `guardStream` — normalize, display fallback, and report.
* `show(BaseException)` — manually display an error in this boundary.
* The default fallback provides “Retry” and “Report” (manual share) actions. Customize via `fallbackBuilder`.

---

## Guard helpers & Result

For non‑UI logic, `core/guard.dart` provides **guard** functions and a small **Result** ADT (`core/result.dart`) for ergonomic flows.

```dart
final res = await guard<User>(() async {
  return api.fetchCurrentUser();
}, source: 'ProfileRepository.fetchCurrentUser');

res.match(
  ok: (user) => emit(ProfileLoaded(user)),
  err: (e)  => emit(ProfileError(e.userMessage)),
);

// or chain:
final fullName = res.map((u) => '${u.first} ${u.last}').unwrapOr('Guest');
```

* `guard<T>` runs the action, returns `Ok(value)` on success. On error, it **normalizes** to a `BaseException`, reports automatically, and returns `Err(e)`.
* `guardSync<T>` does the same synchronously and reports in a fire‑and‑forget task so you don’t block the UI.
* `parser<T>(build, data: raw)` wraps JSON/model construction and throws a typed `ParsingException` when it fails.
* `normalizeError(error, stack, source: '...')` maps:

  * already `BaseException` → passthrough
  * Flutter `PlatformException` → `PlatformOperationException.fromPlatformException`
  * `FormatException` → `ParsingException`
  * otherwise → `UnexpectedException`

Include a `source` string to improve grouping via fingerprints.

---

## Exceptions overview

All exceptions extend `BaseException` (`exceptions/base_exception.dart`) which is immutable, equatable, severity‑aware, and carries `userMessage`, `devMessage`, optional `cause`, optional `stack`, and immutable `metadata`.

Key types:

* **ApiException**
  Wraps HTTP failures and enriches metadata via `HttpStatusCodeInfo` (`helpers.dart`), which provides normalized flags like `isAuthenticationError`, `isRateLimitError`, `isServerError`, derived user/dev messages, and severity mapping.

  ```dart
  final info = HttpStatusCodeInfo(429);
  throw ApiException(
    httpStatusInfo: info,
    endpoint: '/v1/items',
    method: 'GET',
    responseBody: body,
  );
  ```

* **AuthException** and **TokenException**
  Authentication and session lifecycle problems (TokenException uses severity=error by default).

* **DataProcessingException** and **ParsingException**
  For IO/transform/mapping; `ParsingException` automatically includes target type and raw payload.

* **FlutterErrorException**
  Wraps `FlutterErrorDetails` from framework crashes; used by the global bindings.

* **InitializationException** and **ComponentNotInitializedException**
  For bootstrap/setup failures. Initialization is `Severity.critical`.

* **NavigationException**, **RouteNotFoundException**, **InvalidRouteArgumentsException**
  UI routing issues. Defaults to `Severity.warning` and `isReportable=false`.

* **PermissionException**
  Normalized permission errors with `PermissionStatus` and appropriate user messages and severities.

* **PlatformOperationException** and **MediaException**
  Platform channel/OS failures; conveniences for media flows (upload, download, picker, processing, permission, format, size).
  Factory `PlatformOperationException.fromPlatformException(...)` maps Flutter’s `PlatformException` to user/dev messages and severity.

* **StorageException**, **CacheException**, **SecureStorageException**
  Storage/caching failures with operation/key context.

* **ValidationException**
  Input/constraint violations; `Severity.warning`, `isReportable=false` by default.

* **UnexpectedException**
  Catch‑all fallback used during normalization and global handlers.

---

## Transform hooks

Before sanitization, you can transform events:

```dart
ReportEvent tagSource(ReportEvent e) {
  final src = e.exception.metadata['source'] ?? 'unknown';
  final ctx = Map<String, dynamic>.from(e.context)
    ..putIfAbsent('tags', () => <String, dynamic>{})['source'] = src;
  return e.copyWith(context: ctx);
}

final config = ClientConfig(
  // ...
  transforms: [tagSource],
);
```

Use transforms to:

* Add/normalize tags.
* Rewrite dev messages for consistent grouping.
* Attach routing/screen info from your app state.

---

## Extending

### Custom context providers

Implement `ContextProvider` (optionally with `CachedContextProvider`) and add via config or at runtime.

### Custom reporters

Implement `Reporter.send`. Use `generateFile` and `defaultFileName` helpers for share/upload scenarios.

### Custom sanitizers/filters

Compose `SanitizerChain`. Wrap `AllowListFilter`/`DenyListFilter` via `FilterSanitizer` to tailor payload shape to your privacy posture.

---

## Testing & tips

* Prefer `ConsoleReporter` in dev/test. Set `prettyJson: true` when you need full payload dumps.
* Inject dependencies into providers for determinism:

  * `AppContextProvider(packageInfo: fake, battery: fake, connectivity: fake)`
  * `DeviceContextProvider(deviceInfo: fake)`
  * `NetworkContextProvider(connectivity: fake, info: fake)`
* Use `UserContextProvider(manualOnly: true)` to avoid collecting PII automatically.
* Add a meaningful `source` string in `guard(...)` calls to improve dedupe and breadcrumbs.
* If you rely on Outbox, call `flush()` on app resume or when connectivity returns.

---

## Troubleshooting

* **Nothing gets sent**
  Check `Policy` gates:

  * Is your event severity below `minSeverity`?
  * Is `reportHandled` false while your exception was handled?
  * Is the current `environment` in `Policy.environments`?
  * Is `sampling` < 1.0?
  * Are you hitting `rateLimit` or `dedupe` windows?

* **Payload is missing fields**
  A **sanitizer** or **allow list filter** may be removing them. Review your `sanitizers` order and filter paths.

* **Wi‑Fi fields are null**
  Platform permissions or plugin support may prevent access; `NetworkContextProvider` gracefully omits them.

* **Battery level is ‑1**
  That’s the fallback when a platform doesn’t support battery queries.

* **Outbox files accumulate**
  Ensure you include at least one reporter that can succeed in your runtime environment, and call `flush()` at appropriate times.

* **“Report” button does nothing**
  Include `ShareReporter` in your pipeline to enable user‑initiated sharing from the default ErrorBoundary fallback.

---

## FAQ

**Q: What’s considered “manual” reporting?**
A: Set `manual: true` in `createEvent/capture` or use the ErrorBoundary’s “Report” action. Manual mode includes `manualReportOnly` providers (like `UIContextProvider` and any of your own manual‑only providers).

**Q: How are duplicates detected?**
A: The client computes fingerprints from exception type, optional `metadata.source`, top stack frame, and a hash of `devMessage`. Events with the same primary fingerprint within the configured dedupe window are dropped.

**Q: Will providers or reporters ever throw?**
A: No. Providers and the client are defensive and return `{}` / `false` on failure. The pipeline is designed not to crash your app.

**Q: How is HTTP severity determined in `ApiException`?**
A: `HttpStatusCodeInfo` maps status codes to severity: 5xx → error, 401/403 → warning, 404 → info, 429 → warning, otherwise error. It also provides user/dev messages and retry hints you can use in your UX.

**Q: Can I attach binary attachments (screenshots, logs)?**
A: `ReportEvent.attachments` exists in the model. Implement a custom reporter that uploads attachments and reference them in your payload.

---

## File map (what’s in this package)

* **`bug_handler.dart`** — convenience exports for all public APIs.
* **Context**
  `context/provider.dart`, `context/built_in/{app,device,network,ui,user}.dart`
* **Core**
  `core/{client,config,event,guard,outbox,result}.dart`
* **Exceptions**
  `exceptions/*.dart` (API/Auth/Data/FlutterError/Initialization/Navigation/Permission/Platform/PlatformPayment/Storage/Unexpected/Validation)
* **Flutter integration**
  `flutter/{bindings,error_boundary}.dart`
* **Privacy**
  `privacy/{filters,sanitizers}.dart`
* **Reporters**
  `reporters/{reporter,composite_reporter,console_reporter,share_reporter}.dart`
  `reporters/adapters/{sentry,crashlytics}.dart` (stubs)
* **Utilities**
  `helpers.dart` (HTTP status helpers, sensitive fields utilities)

---

## License

Add your license of choice to `LICENSE` in the repository and mention it here. If you plan to publish to pub.dev, include a recognized open‑source license such as MIT, BSD‑3‑Clause, or Apache‑2.0.

---

### Appendix: Practical configuration recipes

**Minimal dev setup**

```dart
ClientConfig(
  environment: 'dev',
  baseProviders: [AppContextProvider(), DeviceContextProvider()],
  additionalProviders: [NetworkContextProvider()],
  sanitizers: [DefaultSanitizer()],
  reporters: [ConsoleReporter(prettyJson: true)],
)
```

**Privacy‑tight production**

```dart
ClientConfig(
  environment: 'prod',
  baseProviders: [AppContextProvider(), DeviceContextProvider()],
  additionalProviders: [
    NetworkContextProvider(),
    UserContextProvider(id: userId, manualOnly: true),
  ],
  sanitizers: [
    DefaultSanitizer(),
    FilterSanitizer(DenyListFilter({'context.network.wifi', '**.email'})),
    MaxDepthSanitizer(maxDepth: 6),
    TruncatingSanitizer(maxString: 1000, maxList: 100, maxMapEntries: 150),
    SizeBudgetSanitizer(maxBytes: 48 * 1024),
  ],
  policy: Policy(
    minSeverity: Severity.error,
    reportHandled: true,
    environments: {'prod'},
    sampling: 1.0,
    rateLimit: RateLimit(10, Duration(minutes: 1)),
    dedupe: DedupeStrategy.windowed(Duration(seconds: 60)),
  ),
  reporters: [
    MyApiReporter(apiClient),
    ShareReporter(subjectPrefix: 'Bug Report'),
  ],
)
```

**Using guards with source labels**

```dart
final res = await guard(() => repo.saveOrder(order),
  source: 'Checkout.saveOrder',
  onSuccess: (_) => BugReportClient.instance.addBreadcrumb('order_saved'),
  onError:  (e) => BugReportClient.instance.addBreadcrumb('order_save_failed', data: {'code': e.runtimeType}),
);
```
