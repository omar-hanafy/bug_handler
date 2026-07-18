---
name: setup-reporting
description: >-
  Use when adding the bug_handler package to a Flutter app for the first time, wiring
  BugReportClient/ClientConfig/BugReportBindings at bootstrap, choosing providers,
  sanitizers, Policy, or reporters, or when initialization questions come up (init order,
  runZonedGuarded, flush on startup, per-environment config).
---

# Set up bug_handler in a Flutter app

Wire the error-reporting pipeline once, at bootstrap, matched to how this app
already boots. Audience: developers integrating `bug_handler` into an app.

## Inspect before writing anything

1. `pubspec.yaml` / `pubspec.lock`: is `bug_handler` present, and which version
   resolves? If it resolves to `0.0.1-dev.*`, STOP - that is the legacy API; use
   the `migrate-legacy-api` skill instead. If absent, add
   `bug_handler: ^1.0.0-dev.6` (or current latest) under dependencies and run
   `flutter pub get`. Require >= 1.0.0-dev.5: earlier dev releases lack
   `captureSafely` and can throw from the reporting path.
2. `main.dart` / `bootstrap.dart`: does the app already use `runZonedGuarded`,
   set `FlutterError.onError`, `PlatformDispatcher.instance.onError`, DI
   (get_it/riverpod container), or initialize Sentry/Crashlytics/Firebase? List
   what exists - this decides the bootstrap style and prevents double wiring.
3. How does the app model environments (flavor enum, String consts, dart-define)?
4. Which state management is used (affects follow-up work, not setup itself).

## Decide the bootstrap style

- App has NO existing zone/error-handler wiring and simple startup:
  use `BugReportBindings.runAppWithReporting(app: () => MyApp(), config: ...)`.
  It installs FlutterError.onError, PlatformDispatcher.onError, runZonedGuarded,
  and an isolate listener, reporting uncaught errors with `handled: false`.
  Import it explicitly: `package:bug_handler/flutter/bindings.dart` (NOT exported
  by the main entrypoint).
- App already owns a zone, DI ordering, or a Sentry init: wire manually -
  `BugReportClient.instance.initialize(config)` inside the existing flow, add the
  three handlers, and call `unawaited(BugReportClient.instance.flush())` after
  `runApp` to drain the offline outbox. Follow Pattern C in
  `../../references/production-patterns.md` exactly. NEVER install both styles;
  double wiring double-reports every crash.

## Build the ClientConfig

Start from Pattern D in `../../references/production-patterns.md`. Decisions to
make with the user's context (defaults in parentheses match production usage):

- `environment`: derive from the app's existing mode/flavor (`mode.name`).
- `baseProviders`: `[AppContextProvider(), DeviceContextProvider()]` is the
  lightweight always-on set. Add `NetworkContextProvider()` only if network state
  matters for triage. `UIContextProvider` needs a BuildContext and is
  manual-report-only; skip at bootstrap.
- `policy`: `Policy(minSeverity: Severity.warning)` in production apps that want
  warnings; the package default is `Severity.error`. Remember LOWER index = MORE
  severe: `warning` is more permissive than `error`. Leave `environments` empty
  unless the app must hard-mute some flavors.
- `reporters`: minimum viable is `[if (kDebugMode) const ConsoleReporter()]` plus
  ONE real backend. If none exists yet, a log-only reporter that returns true
  keeps the outbox from accumulating (Pattern B). Do NOT put `ShareReporter()` in
  an automatic pipeline: its send() opens the platform share sheet and a
  completed share counts as successful delivery. For Sentry/Crashlytics, use the
  `extend-pipeline` skill (the shipped adapter files are empty placeholders).
- `sanitizers`: always include at least `DefaultSanitizer()`. For the full
  privacy chain and ordering rules use the `tune-privacy` skill; a proven default
  chain is in Pattern D.
- User context: register `UserContextProvider` at login via
  `addContextProvider`, clear at logout - not in the static config.

## Verify

1. `dart analyze` the touched files - zero new issues.
2. Temporarily raise a test error behind a debug flag (e.g., a button calling
   `throw StateError('bug_handler smoke test')` inside `guard(..., source: 'Setup.smokeTest')`)
   and confirm the ConsoleReporter block prints with type, severity, and context
   keys, then remove the test code.
3. Confirm exactly one initialization path runs (search for other
   `BugReportClient.instance.initialize` and `runAppWithReporting` calls).
4. If the app targets web: the outbox uses dart:io + path_provider documents
   directory; it is inert on web. Delivery still works; offline queueing does not.

## Failure handling

- `capture` throwing `StateError: BugReportClient is not initialized`: something
  reports before bootstrap finishes. Either reorder, or use `captureSafely`
  (no-op before init) for early paths.
- Reports silently missing after setup: work through
  `../../references/policy-and-delivery.md` gate order (environment, severity,
  handled, sampling, dedupe-by-type, rate limit) before touching reporter code.
- If a referenced reference file is missing in this environment, continue with
  the inline guidance here and read the package source in
  `~/.pub-cache/hosted/pub.dev/bug_handler-<version>/lib/` for signatures.

## Scenario

"Add bug_handler to our app; we have get_it DI and Sentry already initialized in
bootstrap.dart" -> inspect bootstrap order, keep Sentry init but strip its
OnErrorIntegration (Pattern A), initialize the client after DI, hand-wire the
three handlers + flush, config with Console (debug) + SentryReporter, DefaultSanitizer
chain, Policy(minSeverity: warning), then run the smoke test and remove it.
