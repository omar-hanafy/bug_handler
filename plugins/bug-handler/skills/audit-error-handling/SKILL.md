---
name: audit-error-handling
description: >-
  Use when reviewing code in an app that depends on bug_handler - PR review, "check our
  error handling", pre-release audits, or "are we using bug_handler correctly". Finds
  violations of the guard contract: string errors in state, unreported catches, raw
  exceptions crossing repository boundaries, missing source labels, misused isReportable.
---

# Audit error handling against the bug_handler contract

Review-mode counterpart to the `guard-workflow` skill: systematically find
violations, rank them, and report with file:line evidence. Do not rewrite code
unless asked - the deliverable is findings.

## Scope first

Determine the audit surface (a PR diff, a feature directory, or lib/). For a
diff, audit changed files plus the repositories/state they touch. Record the
app's wrapper conventions (guard mixins, base cubits/notifiers, app exception
bases) so findings respect local idiom instead of demanding raw package calls.

## The checklist (each item: how to find it, why it matters)

1. Raw exceptions crossing repository boundaries. In repository/service files,
   every `catch` must rethrow a `BaseException` subclass.
   Find: `grep -n "catch (" <repo files>` then inspect each: throws of
   `Exception(`, `StateError(`, app-local `implements Exception` types, or bare
   `rethrow` of foreign errors are findings. Severity: high (events lose
   severity/user-vs-dev split and bypass reporting).
2. String errors in state. State classes holding `String? errorMessage`/
   `String error` set from `e.userMessage`/`e.toString()`.
   Find: `grep -rn -E "String\??\s+(errorMessage|error\b)" <state files>` plus
   freezed factories `.error(String`. Severity: high for new code, medium for
   pre-existing shared containers (report, do not churn).
3. Unreported catch-and-continue. try/catch in controllers/services that neither
   rethrows a BaseException nor calls guard/captureSafely - the error vanishes.
   Find: catch blocks whose body only logs/returns default. Severity: high when
   the operation can fail for real reasons; note deliberate best-effort swallows
   (cache writes, optimistic UI) as acceptable IF commented as intentional.
4. Wrong guard. Riverpod `AsyncValue.guard(`, hand-rolled `_guarded` helpers, or
   `Future.catchError` where bug_handler reporting was intended.
   Find: `grep -rn "AsyncValue.guard(\|catchError(" lib/`. Severity: medium-high.
5. Missing/unstable `source:` labels. guard/guardSync calls without `source:`,
   or labels that are not stable dotted `ClassName.method` strings.
   Find: `grep -rn -A2 "guard(\|guardSync(" lib/ | grep -v "source:"` (inspect
   matches; multiline calls need manual read). Severity: medium (breaks
   grouping/dedupe quality).
6. `isReportable` misuse. Code that sets `isReportable: false` expecting
   suppression, or reporters that never check it. The pipeline does NOT enforce
   the flag (`../../references/policy-and-delivery.md`). Severity: medium;
   pair each finding with where enforcement should live (reporter skip or
   severity).
7. Localization keys in `userMessage` (e.g. `userMessage: 'somethingWentWrong'`
   camelCase key shapes) that render raw if unmapped. Find: constructor calls
   whose userMessage has no spaces and matches `[a-z]+[A-Z]`. Severity: medium.
8. Parsing without `parser`. `fromJson`/`fromMap` invocations inside repositories
   done bare where the app convention uses `parser(() => ..., data: raw)`.
   Severity: low-medium (errors arrive as FormatException/TypeError instead of
   typed ParsingException with payload).
9. Double bootstrap wiring. Both `runAppWithReporting` AND manual
   FlutterError/PlatformDispatcher/zone handlers -> double reporting.
   Find: `grep -rn "runAppWithReporting\|FlutterError.onError\|PlatformDispatcher" lib/`.
   Severity: high if both present.
10. Reporter contract violations in custom reporters: reading `event.context`
    instead of `event.toMap()` (sanitizer bypass - privacy issue, high),
    returning false for intentional skips (outbox growth, medium), throwing
    (low - swallowed but loses outbox semantics).
11. ShareReporter in the automatic pipeline (share sheet popping on background
    errors + marks delivery successful). Severity: medium.
12. Test integrity: tests asserting on outbox writes in plain flutter test
    (no path_provider - cannot work), or tests weakened to tolerate swallowed
    errors. Severity: medium.

## Report format

Group by severity (high/medium/low). Each finding: `file:line`, one-sentence
violation, one-sentence consequence, the concrete fix direction (respecting app
idiom). End with: counts per category, the top 3 fixes by impact, and explicitly
list categories that came back CLEAN so coverage is visible. If the surface was
a diff, do not report pre-existing issues outside it except as a short
"pre-existing, out of scope" note.

## When NOT to flag

- App-local failure objects at the STATE layer when the repository->guard chain
  is intact and the failure object preserves the BaseException (bridging is a
  legitimate architecture; flag only when the exception is flattened to a string
  or the bridge skips reporting).
- Deliberate, commented best-effort swallows.
- Legacy-API symbols: that is a migration, not an audit finding - point to the
  `migrate-legacy-api` skill and stop auditing files that are pre-migration.

## Scenario

"Review this PR adding checkout error handling" -> scope = diff files + their
repositories; findings: checkout_repository.dart:84 catches DioException and
throws app-local `CheckoutException implements Exception` (high, breaks
contract - suggest extending ApiException); checkout_cubit.dart:41 stores
`e.userMessage` string (high - store the exception, render userMessage in UI);
guard call missing source at checkout_cubit.dart:39 (medium). Categories 6-12
clean. Top fix: make CheckoutException extend ApiException.
