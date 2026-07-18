# Legacy API mapping: bug_handler 0.0.1-dev.x -> 1.0.0-dev.x

The 0.0.1-dev.1..4 line on pub.dev is the ORIGINAL API, preserved on the
`legacy_version` branch and republished under a lower version number so it never
becomes "latest". 1.0.0-dev.x (branch `main`) is the current API. The two are
source-incompatible; this file is the complete translation table.

## How to detect which line a project uses

Any of these means legacy (0.0.1-dev.x):

- `pubspec.yaml` / `pubspec.lock`: `bug_handler` resolved to `0.0.1-dev.*`.
- Imports of barrel files: `package:bug_handler/core/core.dart`,
  `exceptions/exceptions.dart`, `config/config.dart`, `context/context.dart`,
  `reporters/reporters.dart`, `core/error_handler.dart`, `ui/error_display_widget.dart`.
- Symbols: `BugReporter`, `ErrorHandler`, `handleError(`, `wrapper(`,
  `ReportResult`, `ReportConfig`, `sentryDsn`, `ManualReporter`, `SentryReporter`,
  `ErrorDisplayWidget`, `ErrorDisplayConfig`, `reportException(`, `manualReport:`,
  `shouldAutoReport`, `shouldReportToSentry`.
- Sentry types used without a direct `sentry_flutter` dependency (legacy
  re-exported most of sentry_flutter from `core/bug_reporter.dart`).

Current-line projects use: `package:bug_handler/bug_handler.dart`,
`BugReportClient`, `ClientConfig`, `guard(`, `Result`/`Ok`/`Err`, `ReportEvent`.

## Symbol-by-symbol mapping

| Legacy (0.0.1-dev.x) | Current (1.0.0-dev.x) | Notes |
|---|---|---|
| `BugReporter.instance` | `BugReportClient.instance` | |
| `static BugReporter.initialize(start, config: ReportConfig)` | `await BugReportBindings.runAppWithReporting(app: () => MyApp(), config: ClientConfig(...))` or `await BugReportClient.instance.initialize(config)` + your own zone/handlers | Legacy THREW on second init; current silently ignores it |
| `BugReporter.instance.isInitialized()` (method) | `BugReportClient.instance.isInitialized` (getter) | |
| `ReportConfig(currentEnvironment: MyEnv.prod, environments: [...])` | `ClientConfig(environment: 'prod')` | Enum-based -> plain String; the allow-list moved to `Policy(environments: {'prod', ...})` |
| `ReportConfig.minSeverity` | `Policy(minSeverity: ...)` inside `ClientConfig(policy: ...)` | Same index semantics |
| `ReportConfig.sentryDsn` / `enableSentry` | REMOVED. App owns Sentry: add `sentry_flutter` to pubspec, call `SentryFlutter.init` yourself, write a custom `Reporter` that forwards `event.toMap()` | See extend-pipeline skill for the reporter recipe |
| `ReportConfig.onPreSendReport` / `onPreShareReport` (cancelable callbacks) | No direct equivalent. Nearest: `Policy` gates for blanket rules, `transforms` to reshape (cannot cancel), or a wrapper `Reporter` that returns true-without-sending to suppress | Behavior decision required; ask the user which semantics they need |
| `ErrorSeverity` | `Severity` (typedef `ErrorSeverity = Severity` still compiles) | `.shouldAutoReport` / `.shouldReportToSentry` getters are GONE; replace with explicit `Policy` config or reporter-side checks |
| `ErrorHandler.handle(error, stack, source:, userMessage:, devMessage:, severity:, onError:, shouldReport:)` / global `handleError(...)` | `final e = normalizeError(error, stack, source: source); await BugReportClient.instance.captureSafely(e);` | `userMessage`/`devMessage`/`severity` overrides: construct `UnexpectedException(...)` yourself instead of passing them |
| `ErrorHandler.wrap(action, onSuccess:, onError:, shouldReport:, source:)` / global `wrapper(...)` | `guard(action, source:, onSuccess:, onError:)` | Return type changes (next row) |
| `ReportResult<T>{data, exception, didThrow, didReport, onErrorResult, report}` | `Result<T, BaseException>` = `Ok(value)` / `Err(error)` | `didThrow` -> `res.isErr`; `data` -> `res.unwrapOr(...)` / pattern match; `didReport` has NO equivalent (guards report via never-throw path and do not expose delivery outcome - by design, code must not branch on delivery) |
| `shouldReport:` callback per call | Gone. Use `Policy`, or filter inside your Reporter | |
| `parser<T>(action, data:)` | `parser<T>(build, data:)` | UNCHANGED - no edit needed |
| `Report` + `report.send()` / `report.share()` | `ReportEvent` + `BugReportClient.instance.report(event)` / reporter `share` | Events are pre-sanitized now |
| `BugReporter.createReport(e, manualReport: true)` | `BugReportClient.instance.createEvent(e, manual: true)` | Param rename `manualReport` -> `manual` |
| `BugReporter.reportException(e, force: true)` | `capture(e)` / `captureSafely(e)`; no `force` | To bypass gates entirely, call the pipeline's reporters yourself (rare) |
| `clearAdditionalProviders()` | `clearContextProviders()` | |
| `ManualReporter` | `ShareReporter` | `sendReport`/`shareReport` -> `send`/`share`; `generateReportFile` -> `generateFile` |
| `SentryReporter` (built-in) | Write your own (empty stub shipped at `reporters/adapters/sentry.dart` is a placeholder with NO code) | |
| `ErrorDisplayWidget` + `ErrorDisplayConfig` | `ErrorBoundary` + `fallbackBuilder` (`import 'package:bug_handler/flutter/error_boundary.dart'`) | Config object -> builder callback; retry/share -> onRetry/onReport params of the builder |
| Barrel imports (`core/core.dart` etc.) | `package:bug_handler/bug_handler.dart` + `flutter/bindings.dart` + `flutter/error_boundary.dart` + `helpers.dart` as needed | |
| Legacy `BaseException` (const constructor, stack nullable) | Current `BaseException` (NON-const: stack defaults to `StackTrace.current`, metadata deep-copied unmodifiable, Equatable) | Remove `const` from subclass constructors and any `const MyException(...)` call sites |

## Behavior changes with no compile error (audit these manually)

1. `isReportable` WAS enforced (`ReportConfig.shouldSendReport` checked it;
   `reportException` skipped non-reportable). The current pipeline IGNORES it.
   After migration, previously-suppressed exceptions (validation, navigation,
   permission, cancelled payments) can start reporting if their severity passes
   `minSeverity`. Mitigate: keep `minSeverity: Severity.error`, or filter in your
   Reporter.
2. Legacy had no sampling/rate-limit/dedupe. Current defaults add: rate limit
   10/min, dedupe 60s BY EXCEPTION TYPE. High-volume same-type errors will
   collapse; tune `Policy` if you relied on every occurrence arriving.
3. Legacy had no sanitizers. Adding `DefaultSanitizer()` (recommended) will mask
   fields legacy sent in the clear; snapshot-based tests or backend parsers may
   need updates.
4. Legacy `initialize` threw on double-init; current silently ignores the second
   call. Code that relied on catching that StateError changes meaning.
5. Reporting is now never-throw via guards/captureSafely; legacy could throw
   through `report.send()`. Remove any try/catch that existed to protect the app
   from the reporter.

## Dependency changes

Remove from the app if only used via legacy re-exports, or add explicitly if
still used directly: `sentry_flutter` (legacy re-exported it), `flutter_helper_utils`
(legacy used it in Report.toMap). Current package needs none of these; it adds
`dart_helper_utils` internally. SDK floors differ: legacy 0.0.1-dev.4 requires
Dart ^3.11 / Flutter >= 3.41; current 1.0.0-dev.5+ requires Dart ^3.6 /
Flutter >= 3.27.
