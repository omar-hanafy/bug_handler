---
name: diagnose-reporting
description: >-
  Use when bug_handler reports are missing, duplicated, delayed, or unexpected - "nothing
  arrives in Sentry", "capture doesn't send", "errors only show sometimes", outbox files
  piling up in bug_report_outbox, StateError about initialization, or events arriving that
  should have been suppressed.
---

# Diagnose missing, duplicated, or unexpected reports

The pipeline drops events silently by design (`captureSafely` and guards swallow
every failure). Diagnosis is a fixed elimination order - do NOT jump to reporter
code first. Ground truth for every gate:
`../../references/policy-and-delivery.md`.

## Missing reports: eliminate in this exact order

1. Initialization. Was `BugReportClient.instance.initialize` (or
   `runAppWithReporting`) awaited before the failing capture? `capture` throws
   `StateError` when uninitialized, but `captureSafely`/`guard` become silent
   no-ops. Check `BugReportClient.instance.isInitialized` at the capture site.
   Also: a SECOND initialize call is silently ignored; there is no reset.
2. Is the code path even capturing? Bare try/catch, Riverpod `AsyncValue.guard`,
   or app-local exception types caught before any guard means nothing reaches
   the client. Search the failing flow for `guard(`/`captureSafely(`/`capture(`.
3. Policy gates, in pipeline order - first failure wins, none of these enqueue
   to the outbox:
   - environment: `Policy.environments` non-empty and current env not in it;
   - severity: event severity index > `minSeverity` index (critical 0, error 1,
     warning 2, info 3 - `minSeverity: error` DROPS warnings and info; both
     `ValidationException` and `NavigationException` default to warning);
   - handled: `reportHandled: false` drops everything guards capture (guards
     mark `handled: true`; only bindings-caught uncaught errors are false);
   - sampling < 1.0: probabilistic drop;
   - dedupe: same exception TYPE within the window (default 60s) is dropped -
     the primary fingerprint is `fingerprints.first` = runtimeType. Distinct
     errors of one type collapse to the first per window;
   - rate limit (default 10/min): overflow goes to the OUTBOX, not to the
     backend, until `flush()`.
4. Delivery. Add `ConsoleReporter()` temporarily as the first reporter: if the
   console block prints, gates passed and the problem is the real reporter or
   its backend. A reporter returning true "successfully skipped" also counts as
   delivered for the whole composite - check custom reporters' skip logic.
5. Outbox. List `Documents/bug_report_outbox` (device/simulator). Files there =
   delivery failed or rate-limited. Nothing drains it automatically: the app
   must call `BugReportClient.instance.flush()` (app resume / connectivity
   regained / after bootstrap).

## Reports that should NOT have arrived

- `isReportable: false` does NOT suppress delivery - the pipeline never reads
  the flag. Suppress via severity (`minSeverity: error` while the type is
  warning/info) or a skip (return true) in the custom Reporter.
- `additionalContext` keys overwrite provider context keys of the same name.
- `manual: true` captures include `manualReportOnly` providers (UI, opted-in
  user data) - expected for ErrorBoundary "Report" button flows.

## Duplicates

- Two bootstrap wirings (BugReportBindings AND manual FlutterError/
  PlatformDispatcher/zone handlers) double-report every uncaught error - search
  for both styles.
- A reporter that both delivers AND lets Sentry/Crashlytics auto-capture the
  same crash (e.g. Sentry OnErrorIntegration left enabled) duplicates at the
  backend - see Pattern A in `../../references/production-patterns.md`.
- Outbox replay after transient failures re-sends previously-failed events on
  flush; backend-side dedupe by `event.id`/fingerprints handles it.

## Quick probes

```dart
// 1. Are we initialized, and do gates pass? (bypasses capture-site doubts)
debugPrint('init=${BugReportClient.instance.isInitialized}');
final ok = await BugReportClient.instance.report(
  await BugReportClient.instance.createEvent(
    UnexpectedException(devMessage: 'diagnose probe ${DateTime.now()}'),
  ),
);
debugPrint('report() returned $ok'); // false = gated/failed; see order above
```

Vary one dimension at a time: severity (`severity: Severity.critical`),
type (fresh exception class defeats dedupe), environment. Remove probes after.

In plain `flutter test` there is no path_provider: outbox writes throw
internally and are swallowed - do not chase "outbox not written" in unit tests.

## Report findings before fixing

This skill's output is a diagnosis: state WHICH gate or wiring ate the events,
with the evidence (probe output, config values). Propose the minimal fix
(config change, flush call site, reporter skip-logic fix) and apply it only as
the user confirms or the task clearly includes fixing.

## Scenario

"Sentry shows nothing from staging" -> isInitialized true; probe `report()`
returns false; `Policy(environments: {'prod'})` found in config - staging is
gated out. Fix options: add 'staging' to the set or leave by design; chosen fix
verified with the probe returning true and the event visible in Sentry.
