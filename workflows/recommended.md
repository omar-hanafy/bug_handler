# Workflow: Guard‑driven state management with `BaseException`

Purpose: a concise, copy‑pasteable workflow you (and AI assistants) can apply across features. It standardizes error handling so **every failure becomes a `BaseException`**, state managers react consistently, and bug reports stay useful.

---

## Principles

* **One error type to rule them all:** every failure thrown across your app must be a `BaseException` (or subclass).
* **Repository boundary:** convert raw errors (HTTP/Dio/Platform/JSON) into a **domain exception** you control.
* **State managers use guards:** controllers/notifiers/cubits call async work via `guard(...)`, then **store the `BaseException`**, not a string.
* **User/dev messages split:** show `error.userMessage` in UI; keep `error.devMessage` + `metadata` for logs and reports.
* **Fallback safety:** if something throws a non‑`BaseException`, guards **normalize** it into `UnexpectedException` with the original error attached.

---

## Minimal types (use in any state management)

```dart
import 'package:bug_handler/bug_handler.dart';

sealed class UiState<T> {
  const UiState();
}
class UiIdle<T> extends UiState<T> { const UiIdle(); }
class UiLoading<T> extends UiState<T> { const UiLoading(); }
class UiData<T> extends UiState<T> { const UiData(this.data); final T data; }
class UiError<T> extends UiState<T> { const UiError(this.error); final BaseException error; }
```

---

## Repository pattern (always throw `BaseException`)

Create an app‑specific API exception for server quirks, and re‑throw it from repositories.

```dart
import 'package:bug_handler/bug_handler.dart';

// Customize messages/severity for your backend.
class AppApiException extends ApiException {
  AppApiException({
    required HttpStatusCodeInfo info,
    String? endpoint,
    String? method,
    Map<String, dynamic> requestHeaders = const {},
    Object? requestBody,
    Map<String, dynamic> responseHeaders = const {},
    Object? responseBody,
  }) : super(
          httpStatusInfo: info,
          endpoint: endpoint,
          method: method,
          requestHeaders: requestHeaders,
          requestBody: requestBody,
          responseHeaders: responseHeaders,
          responseBody: responseBody,
          userMessage: _userFacing(info),
          severity: _severityOverride(info),
        );

  factory AppApiException.fromResponse({
    required int statusCode,
    required String endpoint,
    required String method,
    Map<String, dynamic> responseHeaders = const {},
    Object? responseBody,
  }) {
    final info = HttpStatusCodeInfo(statusCode);
    return AppApiException(
      info: info,
      endpoint: endpoint,
      method: method,
      responseHeaders: responseHeaders,
      responseBody: responseBody,
    );
  }

  static String _userFacing(HttpStatusCodeInfo i) {
    if (i.isValidationError) return 'Please check your input and try again.';
    if (i.isRateLimitError) return 'You’re doing that too much. Try again shortly.';
    if (i.isTimeoutError) return 'Network timeout. Check your connection and retry.';
    return i.statusUserMessage; // sensible default
  }

  static Severity _severityOverride(HttpStatusCodeInfo i) {
    if (i.isNotFoundError) return Severity.info; // often non-critical
    return i.errorSeverity;
  }
}

class UserRepository {
  final HttpClient _http; // your client

  UserRepository(this._http);

  Future<User> getMe() async {
    try {
      final res = await _http.get('/me'); // example
      if (res.statusCode != 200) {
        throw AppApiException.fromResponse(
          statusCode: res.statusCode,
          endpoint: '/me',
          method: 'GET',
          responseHeaders: res.headers,
          responseBody: res.body,
        );
      }
      return parser(() => User.fromJson(res.json), data: res.body);
    } on BaseException {
      rethrow; // already normalized
    } catch (e, s) {
      // Unknown → consistent domain error
      throw UnexpectedException(
        userMessage: 'Something went wrong. Please try again.',
        devMessage: 'Unexpected error in UserRepository.getMe',
        cause: e,
        stack: s,
      );
    }
  }
}
```

---

## State management recipes

> The controller/notifier/cubit **must** call repository methods inside `guard(...)`
> and transition state with a `BaseException` (not a string).

### A) Riverpod (`StateNotifier`)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bug_handler/bug_handler.dart';

class UserController extends StateNotifier<UiState<User>> {
  UserController(this._repo) : super(const UiIdle());
  final UserRepository _repo;

  Future<void> load() async {
    state = const UiLoading();
    final res = await guard<User>(
      () => _repo.getMe(),
      source: 'UserController.load',
    );
    res.match(
      ok: (u) => state = UiData(u),
      err: (e) => state = UiError(e),
    );
  }
}

final userControllerProvider =
    StateNotifierProvider<UserController, UiState<User>>(
  (ref) => UserController(ref.watch(userRepositoryProvider)),
);
```

### B) Provider (`ChangeNotifier`)

```dart
import 'package:flutter/foundation.dart';
import 'package:bug_handler/bug_handler.dart';

class UserModel extends ChangeNotifier {
  UserModel(this._repo);
  final UserRepository _repo;

  UiState<User> state = const UiIdle();

  Future<void> load() async {
    state = const UiLoading();
    notifyListeners();

    final res = await guard<User>(
      () => _repo.getMe(),
      source: 'UserModel.load',
    );

    res.match(
      ok: (u) => state = UiData(u),
      err: (e) => state = UiError(e),
    );
    notifyListeners();
  }
}
```

### C) BLoC (`Cubit`) — optional

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bug_handler/bug_handler.dart';

class UserCubit extends Cubit<UiState<User>> {
  UserCubit(this._repo) : super(const UiIdle());
  final UserRepository _repo;

  Future<void> load() async {
    emit(const UiLoading());
    final res = await guard<User>(
      () => _repo.getMe(),
      source: 'UserCubit.load',
    );
    res.match(
      ok: (u) => emit(UiData(u)),
      err: (e) => emit(UiError(e)),
    );
  }
}
```

---

## UI usage

Render errors using the exception object. Prefer `userMessage` for end users.

```dart
Widget buildError(UiError e) {
  return Column(
    children: [
      Text(e.error.userMessage),
      if (!kReleaseMode) // optional: show dev details in non‑prod
        Text('${e.error.runtimeType}: ${e.error.devMessage}'),
      TextButton(
        onPressed: () async {
          // Optional: let users report manually; includes manual-only context.
          await BugReportClient.instance.capture(e.error, manual: true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted')),
          );
        },
        child: const Text('Report'),
      ),
    ],
  );
}
```

> Alternative: wrap screens in `ErrorBoundary` and trigger actions via `boundary.guardAsyncCallback(...)`. That fallback already offers “Retry” and “Report”.

---

## Guard behavior summary

* `guard<T>(...)` executes your function.

  * On success → `Ok<T>`.
  * On error → **normalizes** to `BaseException`, **reports it**, returns `Err<BaseException>`.
* Use `source: 'Feature.Controller.action'` to help grouping and dedupe.
* Use `parser(() => Model.fromJson(...), data: raw)` to convert `FormatException` into a typed `ParsingException`.

---

## What to throw where

* **HTTP:** throw `AppApiException` (or `ApiException`) enriched with status, endpoint, method, request/response snippets.
* **Auth/Token:** `AuthException` / `TokenException`.
* **Permissions:** `PermissionException(permission: 'camera', status: ...)`.
* **Platform channels:** `PlatformOperationException.fromPlatformException(e, operation: 'camera_capture')`.
* **Storage/Cache:** `SecureStorageException` / `CacheException`.
* **Validation:** `ValidationException(userMessage: 'Please fill all required fields.', validationErrors: {...})` — usually not auto‑reported.
* **Unknown:** `UnexpectedException(devMessage: 'Context...', cause: e, stack: s)`.

---

## Checklist (for developers and AI assistants)

* Repositories/services: wrap calls in `try/catch`; **re‑throw** a specific `BaseException` subclass.
* Controllers/notifiers/cubits: call work via `guard(...)`; store **`UiError(BaseException)`** on failure.
* UI: read `error.userMessage`; optional “Report” uses `BugReportClient.instance.capture(error, manual: true)`.
* Add `source:` everywhere you use `guard` (stable, searchable string).
* Prefer preparing **custom exceptions** per domain so your state has useful metadata and your reports are rich.
* All other package features (sanitizers, filters, outbox, reporters) are optional; enable them via `ClientConfig` as needed.

---

## Minimal runtime wiring (once in `main()`)

```dart
await BugReportBindings.runAppWithReporting(
  app: () => const MyApp(),
  config: ClientConfig(
    environment: kReleaseMode ? 'prod' : 'dev',
    baseProviders: [AppContextProvider(), DeviceContextProvider()],
    additionalProviders: [NetworkContextProvider()],
    sanitizers: [DefaultSanitizer()],
    policy: const Policy(minSeverity: Severity.error, reportHandled: true),
    reporters: [ConsoleReporter(enabled: !kReleaseMode), ShareReporter()],
  ),
);
```

This workflow keeps failures typed, states predictable, and reports actionable. Use it for every feature; when a new task might throw arbitrary errors, wrap it and **re‑throw something you understand**.
