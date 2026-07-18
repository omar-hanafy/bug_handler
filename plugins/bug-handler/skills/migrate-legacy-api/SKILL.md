---
name: migrate-legacy-api
description: >-
  Use when a project depends on bug_handler 0.0.1-dev.x or contains its legacy API -
  BugReporter, ErrorHandler, handleError, wrapper, ReportResult, ReportConfig, sentryDsn,
  ManualReporter, SentryReporter, ErrorDisplayWidget, or imports like
  package:bug_handler/core/error_handler.dart - and needs to move to the current
  1.0.0-dev.x API.
---

# Migrate bug_handler 0.0.1-dev.x (legacy) -> 1.0.0-dev.x (current)

Supported path: any 0.0.1-dev.1..4 project -> 1.0.0-dev.5 or later (recommend
latest). The lines are source-incompatible; this is a mechanical-plus-judgment
migration, not a version bump. Complete symbol table, behavior changes, and
detection patterns: `../../references/legacy-api-mapping.md` (read it fully
before editing). Worked before/after example:
`../../fixtures/migration/` (`legacy_before/` vs `current_after/`).

## Preconditions

1. Confirm the project is actually on legacy: `pubspec.lock` resolves
   `bug_handler` to `0.0.1-dev.*`, or legacy symbols/imports from the mapping's
   detection list appear in `lib/`. If already on 1.0.0-dev.x with no legacy
   symbols, STOP and say so - nothing to migrate.
2. Clean git state (or a dedicated branch). The migration touches bootstrap;
   do not mix with other work.
3. SDK compatibility check: current line needs Dart >= 3.6 / Flutter >= 3.27
   (legacy 0.0.1-dev.4 already required newer, so this is normally satisfied).
4. Inventory the blast radius BEFORE editing - run and record counts:

```bash
grep -rn -E "BugReporter|ErrorHandler|handleError\(|wrapper\(|ReportResult|ReportConfig|ManualReporter|SentryReporter|ErrorDisplayWidget|reportException\(|manualReport:|shouldAutoReport|shouldReportToSentry" lib/ --include='*.dart'
grep -rn "package:bug_handler/" lib/ --include='*.dart' | grep -vE "bug_handler/bug_handler.dart"
```

## Ordered migration steps

1. `pubspec.yaml`: `bug_handler: ^1.0.0-dev.6` (or current latest). If the app
   used Sentry through the legacy package (`sentryDsn` set, Sentry types without
   a direct dep), add `sentry_flutter` explicitly now - legacy re-exported it;
   current does not. `flutter pub get`.
2. Imports: replace every legacy barrel import (`core/core.dart`,
   `exceptions/exceptions.dart`, `config/config.dart`, `context/context.dart`,
   `reporters/reporters.dart`, `core/error_handler.dart`,
   `core/bug_reporter.dart`) with `package:bug_handler/bug_handler.dart`; add
   `flutter/error_boundary.dart` where `ErrorDisplayWidget` was used,
   `helpers.dart` where `HttpStatusCodeInfo` is constructed.
3. Bootstrap: `BugReporter.initialize(start, config: ReportConfig(...))` becomes
   `BugReportBindings.runAppWithReporting(app:, config: ClientConfig(...))` (or
   manual wiring, Pattern C in `../../references/production-patterns.md`).
   Config field moves per the mapping table: enum environment -> String;
   minSeverity -> `Policy`; sentryDsn/enableSentry -> app-owned SentryFlutter.init
   + custom `SentryReporter` (Pattern A). `onPreSendReport`/`onPreShareReport`
   need a HUMAN DECISION - see judgment cases below.
4. Call sites, mechanical layer:
   - `wrapper(action, source:, onSuccess:, onError:, shouldReport:)` ->
     `guard(action, source:, onSuccess:, onError:)`;
   - `handleError(e, s, source:, ...)` -> `captureSafely(normalizeError(e, s, source: source))`;
   - `ReportResult` consumption -> `Result`: `didThrow` -> `isErr`; `.data` ->
     `unwrapOr`/pattern-match; `didReport` -> DELETE the branch (delivery
     outcome is intentionally not exposed; code must not depend on it);
   - `reportException(e)` -> `captureSafely(e)`; `manualReport:` -> `manual:`;
   - `ManualReporter` -> `ShareReporter`; `ErrorDisplayWidget(config:)` ->
     `ErrorBoundary(fallbackBuilder:)`;
   - `parser(...)` - unchanged, leave as is.
5. Exception subclasses: remove `const` from constructors/call sites of
   `BaseException` subclasses (current base is non-const). `ErrorSeverity` still
   compiles via typedef; optionally rename to `Severity`. Replace uses of the
   removed `severity.shouldAutoReport` / `shouldReportToSentry` getters with
   `Policy` config or reporter-side checks.
6. Format and analyze: `dart format .` then `dart analyze` - iterate until zero
   errors. Then re-run the step-0 greps: expected result is zero legacy symbols.

## Cases requiring human judgment (ask, do not guess)

- `shouldReport:` per-call callbacks and `onPreSendReport` cancel hooks: current
  API has no cancelable pre-send. Options: encode blanket rules in `Policy`,
  move filtering into the custom Reporter (skip -> return true), or drop the
  behavior. Present the options with the original callback's logic quoted.
- `isReportable` reliance: legacy ENFORCED it; current ignores it. Grep
  `isReportable` - if the app sets it false anywhere expecting suppression,
  decide per type: keep `minSeverity: error` (suppresses the warning/info
  defaults), or add reporter-side skip logic. This is the migration's main
  silent behavior change.
- Delivery-outcome branching (`didReport`): any real logic hanging off it must
  be redesigned - flag each site.
- New runtime gates: current defaults add rate limit 10/min and 60s dedupe BY
  EXCEPTION TYPE. If the app counted on every occurrence arriving (metrics via
  error volume), tune `Policy(rateLimit:, dedupe:)` deliberately.

## Validation

1. `dart analyze` clean; app builds for its primary platform.
2. Boot smoke test: app starts, one forced error (temporary debug button through
   `guard`) reaches the configured reporter, then remove the probe.
3. If Sentry was migrated: verify one event arrives in Sentry and that crashes
   are not DOUBLE-reported (OnErrorIntegration removed - Pattern A).
4. Run the app's test suite; fix fallout without weakening tests.
5. Expected residual warnings: none from this package. `ErrorSeverity` usages
   are legal (typedef) - do not chase them unless the user wants the rename.

## Edge cases

- Already-migrated project (no legacy symbols, current version): report
  "already on current API", change nothing.
- Unsupported input: versions other than 0.0.1-dev.x (e.g. a fork, or the
  pre-publication `bug_reporting_system` package name): the mapping still
  mostly applies (same legacy shape), but say explicitly that this exact
  source version is not a published supported path and proceed only with the
  user's consent, mapping symbol-by-symbol.
- Mixed state (some files migrated): finish per-file using the step-4 greps as
  the worklist; do not leave both `BugReporter` and `BugReportClient` wired.
- Rollback: `git checkout` the migration branch away, restore pubspec.lock via
  `flutter pub get`. No on-disk state migrates (legacy had no outbox), so
  rollback is source-only.

## Scenario

App on 0.0.1-dev.4 with `wrapper()` in 40 call sites, Sentry via sentryDsn ->
inventory greps; pubspec bump + explicit sentry_flutter; bootstrap rewritten to
runAppWithReporting + SentryReporter (Pattern A); 40 wrapper sites -> guard with
kept source labels; two `didReport` branches flagged to the user (dropped after
confirmation); analyze clean; smoke event visible in Sentry exactly once.
