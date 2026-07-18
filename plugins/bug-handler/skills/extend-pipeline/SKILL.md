---
name: extend-pipeline
description: >-
  Use when connecting bug_handler to a delivery backend or enriching its reports - writing
  a custom Reporter (Sentry, Crashlytics, Slack, first-party HTTP endpoint), a custom
  ContextProvider (feature/session/cart context), or an EventTransform. Also use when
  someone tries to use the shipped Sentry/Crashlytics "adapters" (they are empty
  placeholder files).
---

# Extend the bug_handler pipeline

Three extension points: `Reporter` (delivery), `ContextProvider` (enrichment),
`EventTransform` (reshaping). The shipped
`reporters/adapters/{sentry,crashlytics}.dart` files are EMPTY placeholders -
never import them; write the reporter in the app.

## Custom Reporter contract (the rules that are not obvious)

1. `send(event)` returns `true` iff delivered. Return `false` ONLY for genuine
   delivery failure - false re-queues the event into the durable outbox for
   retry on the next `flush()`.
2. When you skip an event on purpose (severity filter, `isReportable` policy,
   noise suppression), return TRUE. Returning false for skips makes the outbox
   grow forever with events you will never send.
3. Never throw. Wrap the body in try/catch and return false on failure
   (CompositeReporter swallows throws, but a throw still loses the outbox
   enqueue distinction you want).
4. Read the payload from `event.toMap()`. It is the sanitized payload embedded
   by the client. Building output from `event.context`/`event.exception` fields
   directly bypasses every sanitizer - a privacy bug.
5. After outbox replay, `event.exception` is a `SerializedException`, not the
   original subtype. Type checks like `event.exception is ValidationException`
   silently stop matching for replayed events; prefer payload fields
   (`payload['exception']['type']`) when filtering must survive replay.
6. Reporters run in ClientConfig order inside a CompositeReporter; ANY true
   marks the whole delivery successful (no outbox). Order side-effecting
   reporters first if that matters.

Full working `SentryReporter` (transport-only Sentry, skip semantics, level
mapping) and `LoggerReporter` templates: Patterns A and B in
`../../references/production-patterns.md`. For Sentry, also apply the bootstrap
side of Pattern A (strip `OnErrorIntegration` so Sentry does not double-capture
what bug_handler already owns).

## Custom ContextProvider contract

```dart
class CartContextProvider extends ContextProvider with CachedContextProvider {
  const CartContextProvider(this.cart);
  final CartService cart;

  @override
  String get name => 'cart';                 // key in event context

  @override
  Duration get cacheDuration => const Duration(seconds: 30);

  @override
  Future<Map<String, dynamic>> collect() async => {
        'items': cart.items.length,
        'total': cart.total,
      };
}
```

Rules:
- With `CachedContextProvider`, override `collect()`, NOT `getData()` (the mixin
  owns getData: TTL cache + in-flight dedupe + never-throw).
- Without the mixin, `getData()` must never throw - return `{}` on failure.
- Return JSON-encodable values only (String/num/bool/List/Map); enums via
  `.name`, DateTime via `toIso8601String()`.
- `manualReportOnly => true` for heavy or sensitive data (collected only when
  `manual: true`, i.e. user-initiated reports).
- Empty maps are dropped by `validateData`; that is fine.
- Register: config-time in `baseProviders`/`additionalProviders`, or runtime via
  `BugReportClient.instance.addContextProvider(...)` (dedupes by equality;
  lifecycle-bound data like the current user belongs at runtime with
  `clearContextProviders()` on logout).
- Sensitive keys (email, token, ids) still pass through the sanitizer chain -
  verify masking with the `tune-privacy` skill if you add any.

## EventTransform

`ReportEvent Function(ReportEvent)`, applied in order BEFORE sanitization.
Use for tagging/normalizing (e.g., copy `metadata['source']` into a context
tag, rewrite devMessages for grouping). Transforms cannot cancel delivery -
that is Policy/Reporter territory. Keep them pure; return `e.copyWith(...)`.

## Verify

1. `dart analyze` + `dart format` on new files.
2. Unit-test the reporter contract without the client: construct a
   `ReportEvent` (or `SerializedException`-based one via
   `ReportEvent.fromMap`) and assert send() returns true/false per your matrix,
   and that skipped events return true.
3. Wire into ClientConfig and run the app-level smoke test from the
   `setup-reporting` skill; confirm the backend received the sanitized payload
   (spot-check that a known-sensitive field arrives masked).
4. If the reporter can be disabled by config (missing DSN), confirm the
   pipeline still contains at least one always-true reporter in that mode or
   accept outbox accumulation knowingly.

## Scenario

"Send our bug_handler reports to Crashlytics" -> new `CrashlyticsReporter extends
Reporter` in the app's reporting module: `send` maps
`event.toMap()` into `FirebaseCrashlytics.instance.recordError(exception:
payload['exception']['devMessage'], reason: ..., information: [...])`, returns
false only on thrown delivery errors; registered after ConsoleReporter; unit
test with a fabricated event; smoke test confirms masked payload in console.
