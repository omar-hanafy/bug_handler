# Policy gates and delivery semantics (exact, from source)

This is the ground truth for "why did/didn't my report send". Order matters and
several behaviors are non-obvious.

## The exact pipeline for one event

`capture(e)` = `createEvent(e)` then `report(event)`.

### createEvent (always succeeds unless client uninitialized)

1. Throws `StateError` if `initialize()` was never called (only `captureSafely`
   is a safe no-op when uninitialized).
2. Collects context: baseProviders, then additionalProviders + runtime providers.
   Providers with `manualReportOnly == true` are skipped unless `manual: true`.
   Provider errors are swallowed; failing providers just drop their section.
3. Builds the raw event: context gets `environment`, `handled`, provider maps,
   then your `additionalContext` (can overwrite provider keys).
4. Applies `transforms` in order (each `ReportEvent -> ReportEvent`).
5. Runs every sanitizer over `event.toMap()` and embeds the result as the
   event's payload. Reporters and the outbox see ONLY this sanitized payload.

### report (returns false for any drop; true only when a reporter succeeded)

Gate order - the first failing gate wins and NOTHING later runs:

1. Environment: `Policy.environments` non-empty and current environment not in
   the set -> dropped. NOT enqueued to outbox.
2. Severity: `event.exception.severity.index > minSeverity.index` -> dropped.
   (index order: critical 0, error 1, warning 2, info 3). NOT enqueued.
3. Handled: `reportHandled == false` and `event.handled == true` -> dropped.
   NOT enqueued. (guard/guardSync/capture default handled: true; bindings pass
   handled: false for uncaught errors.)
4. Sampling: `sampling < 1.0` and random draw fails -> dropped. NOT enqueued.
5. Dedupe: same PRIMARY fingerprint seen within the dedupe window -> dropped.
   NOT enqueued. THE PRIMARY FINGERPRINT IS `fingerprints.first`, WHICH IS THE
   EXCEPTION runtimeType. Two different errors of the same exception type within
   the window deduplicate against each other even with different messages,
   sources, and stacks. Distinct types are never deduped against each other.
6. Rate limit: window saturated -> event IS enqueued to outbox, report returns
   false.
7. Delivery: `CompositeReporter.send` fans out; any reporter returning true =>
   success. All false/throwing => event enqueued to outbox, returns false.

### Outbox truth table

| Cause of non-delivery | Goes to outbox? |
|---|---|
| environment / severity / handled gate | No |
| sampling / dedupe drop | No |
| rate limit | Yes |
| every reporter failed or threw | Yes |
| a reporter returned true (incl. ShareReporter share sheet) | No (success) |

`flush()` re-sends pending outbox files through the CURRENT pipeline and deletes
acknowledged ones. Outbox items are rehydrated as `SerializedException`; the
original exception subtype is NOT restored, so type-based logic in reporters must
tolerate `SerializedException` after a replay. Call `flush()` on app resume or
connectivity restore; nothing calls it automatically.

## Traps that cost real debugging time

1. `isReportable` is never enforced. `ValidationException`, `NavigationException`,
   `PermissionException`, `PlatformPaymentException.cancelled` default it to
   false, but they still deliver if severity passes the gate. If you need the
   drop, filter in your Reporter (`if (!eventLooksReportable) return true;`) or
   keep `minSeverity` at `error` (their severities are mostly warning/info).
   When a custom Reporter intentionally skips an event, return TRUE (treat as
   handled) - returning false re-queues it to the outbox forever.
2. Dedupe-by-type (gate 5). A burst of distinct `UnexpectedException`s within
   60s collapses to one delivery. Give errors distinct types or pass a stable
   `metadata['source']` AND expect only the first per type per window. Widen or
   shrink via `DedupeStrategy.windowed(Duration(...))`.
3. Severity direction confuses people: LOWER index = MORE severe.
   `minSeverity: Severity.warning` is MORE permissive than `Severity.error`.
4. `ShareReporter` in the automatic pipeline: `send()` opens the share sheet. In
   a background/auto path this pops UI at the user and a completed share marks
   the whole composite delivery successful (skipping outbox). Only include it
   when you intend the share UX (e.g., manual reports, internal builds).
5. `captureSafely` swallows EVERYTHING (init missing, provider crashes, reporter
   crashes, outbox write failures). Silence is not proof of delivery; check
   reporter-side logs (`ConsoleReporter(enabled: kDebugMode)`) when validating.
6. `initialize()` called twice: the second config is silently ignored. There is
   no reset; in tests, order suites so uninitialized-behavior tests run first
   (see the package's own test/never_throw_invariant_test.dart).
7. Rate limiter default is 10 events/minute; an error storm quietly diverts the
   overflow to the outbox where it waits for `flush()`.
8. Plain `flutter test` has no path_provider, so outbox writes throw internally;
   `captureSafely`/guards swallow that. Do not assert on outbox behavior in unit
   tests without a path_provider stub.

## Never-throw matrix (what is safe where)

| API | Before initialize | Reporter throws | Outbox write fails |
|---|---|---|---|
| `captureSafely` | no-op | swallowed | swallowed |
| `guard` / `guardSync` | Err returned, reporting skipped silently | swallowed | swallowed |
| `ErrorBoundary` helpers | fallback still shows | swallowed | swallowed |
| `BugReportBindings` handlers | n/a (it initializes first) | swallowed | swallowed |
| `capture` / `report` / `flush` | StateError | propagates via return false / outbox | propagates |

The invariant "reporting must never change the outcome of guarded code" is locked
by test/never_throw_invariant_test.dart in the package repo. Preserve it when
proposing package changes.
