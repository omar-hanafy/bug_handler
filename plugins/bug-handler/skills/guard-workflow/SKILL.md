---
name: guard-workflow
description: >-
  Use when writing or refactoring feature code in an app that depends on bug_handler -
  repositories/services that can fail, cubits/blocs/notifiers/controllers that load data,
  error states, try/catch blocks, or "handle errors properly" requests. Also use when
  choosing which exception type to throw or how errors should reach the UI.
---

# Guard-driven error handling for features

The package's core contract, applied to everyday feature work. One rule chain:
repositories throw typed `BaseException` subclasses; state managers run work
through `guard(...)` with a `source:` label; state stores the `BaseException`
object; UI renders `error.userMessage`. Reporting happens inside `guard` and
never throws.

## Inspect before writing

1. Confirm the app uses bug_handler >= 1.0.0-dev.5 (pubspec.lock) and is on the
   current API (`BugReportClient` exists; if you see `BugReporter`/`ErrorHandler`,
   switch to the `migrate-legacy-api` skill first).
2. Find the app's existing conventions BEFORE introducing new ones:
   - a guard wrapper/mixin (search `guard<` and `guard(`) - reuse it;
   - existing `BaseException` subclasses (search `extends ApiException`,
     `extends BaseException`) - throw those, do not invent parallels;
   - the state shape used by sibling features (sealed classes, freezed, enums).
3. Identify the state management library; recipes below adapt to it.

## The five rules

1. Repository/service boundary: catch foreign errors (Dio, platform, JSON) and
   rethrow a specific `BaseException` subclass. Pick the type from
   `../../references/exceptions-catalog.md`. Already-`BaseException` errors pass
   through (`on BaseException { rethrow; }`); unknown ones become
   `UnexpectedException(cause: e, stack: s, devMessage: 'context...')`.
2. Parsing boundary: wrap model construction in
   `parser(() => User.fromJson(json), data: json)` - it throws a typed
   `ParsingException` carrying the raw payload.
3. State manager: call the work through `guard(action, source: 'ClassName.method')`
   (or the app's wrapper over it). Never bare try/catch in controllers, and never
   Riverpod's `AsyncValue.guard` where reporting is intended - it neither
   normalizes nor reports nor labels the error.
4. State stores the exception object: `BaseException? error` (or a sealed variant
   holding it). Do NOT store `e.userMessage` strings - that discards severity,
   type, and metadata the UI and retry logic need. If the app's shared state
   container only holds a String today, keep the feature consistent with its
   siblings but ALSO surface the typed object where the feature owns its state
   class, and tell the user about the container limitation.
5. UI renders `error.userMessage`; dev details (`runtimeType`, `devMessage`)
   only behind a debug flag. `userMessage` must be a resolved human string -
   never a localization KEY (a real production bug class: raw keys rendered to
   users). Resolve l10n at construction or render time explicitly.

`source:` convention: stable dotted `ClassName.method` (e.g.
`'AuthController.login'`). It feeds fingerprints, grouping, and dedupe.

## Recipes per state management

Follow Pattern E in `../../references/production-patterns.md` for full Riverpod
and Bloc examples (runner mixin, sealed state, `switch (res) { case Ok... }`).
Compressed shape for any library:

```dart
emitLoading();
final res = await guard(() => repo.fetch(), source: 'XController.load');
res.match(
  ok: (data) => emitLoaded(data),
  err: (e) => emitError(e),   // the BaseException itself
);
```

`guardSync` for synchronous compute (reporting is fire-and-forget);
`res.unwrapOr(fallback)` / `map` / `andThen` for chaining;
`ErrorBoundary.of(context).guardAsyncCallback` when a widget-local fallback UI is
wanted (import `package:bug_handler/flutter/error_boundary.dart`).

## Custom domain exceptions

When the backend has semantics the stock types miss, subclass per the
`AppApiException` template in `../../references/exceptions-catalog.md`
(remember `import 'package:bug_handler/helpers.dart'` for `HttpStatusCodeInfo`).
Set `severity` deliberately - it is the delivery gate. `isReportable: false`
documents intent but is NOT enforced by the pipeline; do not rely on it to
suppress delivery.

## Verify

1. `dart analyze` on touched files; `dart format` them.
2. Run the feature's existing tests; add/extend a test asserting the error path
   emits the typed error state (construct the repository to throw a
   `BaseException` subclass and assert `state.error` is that instance - Equatable
   makes this exact).
3. Grep your diff for `catch (` - every catch in repositories must rethrow a
   `BaseException`; every catch in controllers should not exist (guard replaced it).
4. Do not weaken existing tests or swallow errors to make flows "pass".

## When NOT to apply

- Code with no failure modes (pure widgets, constants).
- The app deliberately bridges to its own failure objects at the state boundary:
  keep the repository->guard rules, map `Err(e)` into the app's failure type at
  the edge, and preserve `e` (not just a message) inside it when possible.

## Scenario

"Add a favorites feature: repository + cubit + screen" -> repository methods
throw `AppApiException.fromResponse(...)` / use `parser` for models; cubit's
`load()`/`toggle()` run through `guard(source: 'FavoritesCubit.load')`; state is
`sealed FavoritesState` with `FavoritesError(BaseException error)`; screen shows
`error.userMessage` with a retry that re-calls the cubit.
