# Production integration patterns

Patterns distilled from real apps shipping bug_handler 1.0.0-dev.5. Use them as
templates; adapt names to the host project.

## Pattern A: Sentry as transport only (custom Reporter)

The shipped Sentry adapter file is empty; this is the proven shape. bug_handler
owns capture/normalize/sanitize/policy; Sentry is a dumb delivery sink.

```dart
// pubspec: add sentry_flutter yourself.
import 'package:bug_handler/bug_handler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class SentryReporter extends Reporter {
  const SentryReporter();

  @override
  Future<bool> send(ReportEvent event) async {
    // Intentional skips return TRUE so the event is not re-queued to the outbox.
    if (_shouldSkip(event)) return true;
    try {
      // ALWAYS read the sanitized payload. event.context would bypass sanitizers.
      final payload = event.toMap();
      await Sentry.captureEvent(
        SentryEvent(
          message: SentryMessage(event.exception.devMessage),
          level: switch (event.exception.severity) {
            Severity.critical => SentryLevel.fatal,
            Severity.error => SentryLevel.error,
            Severity.warning => SentryLevel.warning,
            Severity.info => SentryLevel.info,
          },
          fingerprint: event.fingerprints,
          extra: payload,
        ),
      );
      return true;
    } catch (_) {
      return false; // genuine delivery failure -> client enqueues to outbox
    }
  }

  bool _shouldSkip(ReportEvent event) {
    // isReportable is NOT enforced by the pipeline; enforce your policy here.
    if (event.exception.severity == Severity.info) return true;
    if (!event.exception.isReportable) return true;
    return false;
  }
}
```

Bootstrap side: initialize Sentry yourself and disable its automatic Dart error
capture so bug_handler stays the single owner of capture:

```dart
await SentryFlutter.init(
  (options) {
    options
      ..dsn = dsn
      ..environment = mode.name;
    // Keep ONLY transport: remove Sentry's own error hooks so they do not
    // double-report what bug_handler already captures.
    options.integrations.removeWhere((i) => i is OnErrorIntegration);
  },
);
```

The same Reporter shape applies to Crashlytics
(`FirebaseCrashlytics.instance.recordError(...)`, return true/false) or a
first-party HTTP endpoint (`postJson('/errors', event.toMap())`).

## Pattern B: log-only reporter while backend is undecided

```dart
class LoggerReporter extends Reporter {
  const LoggerReporter(this.logger);
  final Logger logger;

  @override
  Future<bool> send(ReportEvent event) async {
    final line = '[bug] ${event.exception.runtimeType}: ${event.exception.devMessage}';
    switch (event.exception.severity) {
      case Severity.critical || Severity.error: logger.error(line);
      case Severity.warning: logger.warn(line);
      case Severity.info: logger.info(line);
    }
    return true; // local logging counts as delivered; nothing accumulates in outbox
  }
}
```

## Pattern C: bootstrap without BugReportBindings (manual zone)

Both known production apps wire the zone by hand for control over ordering with
DI, Sentry, and pre-init fallbacks:

```dart
Future<void> main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // ... DI setup, env loading ...
    await BugReportClient.instance.initialize(buildConfig(mode));

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(BugReportClient.instance
          .captureSafely(FlutterErrorException(details), handled: false));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(BugReportClient.instance.captureSafely(
        normalizeError(error, stack, source: 'PlatformDispatcher.onError'),
        handled: false,
      ));
      return true;
    };

    runApp(const MyApp());
    // Drain offline queue from previous runs once the pipeline is live.
    unawaited(BugReportClient.instance.flush());
  }, (error, stack) {
    unawaited(BugReportClient.instance.captureSafely(
      normalizeError(error, stack, source: 'runZonedGuarded'),
      handled: false,
    ));
  });
}
```

Use `BugReportBindings.runAppWithReporting` instead when the app has no such
ordering constraints; it does all of the above (plus an isolate error listener)
in one call. Do not use both: double wiring double-reports.

## Pattern D: config shapes seen in production

```dart
ClientConfig(
  environment: mode.name,                      // enum -> .name string
  baseProviders: [AppContextProvider(), DeviceContextProvider()],
  policy: const Policy(minSeverity: Severity.warning),
  reporters: [
    if (kDebugMode) const ConsoleReporter(),
    if (dsn.isNotEmpty) const SentryReporter(),
  ],
  sanitizers: [
    // Deny FIRST when stripping fields sanitizers would otherwise just mask.
    FilterSanitizer(DenyListFilter({
      'context.app.buildSignature',
      'context.device.fingerprint',
      'context.device.identifierForVendor',
      'context.device.hostName',
      'context.device.userName',
    })),
    DefaultSanitizer(),
    const MaxDepthSanitizer(maxDepth: 8),
    const TruncatingSanitizer(maxString: 2000, maxList: 100, maxMapEntries: 100),
    SizeBudgetSanitizer(maxBytes: 64 * 1024),
  ],
)
```

User context after login (runtime provider, not config-time):

```dart
void onLogin(User u) {
  BugReportClient.instance
    ..clearContextProviders()
    ..addContextProvider(UserContextProvider(id: u.id, email: u.email));
}
void onLogout() => BugReportClient.instance.clearContextProviders();
```

## Pattern E: state-management integration shapes

The package contract: repositories throw `BaseException` subclasses; state layer
calls `guard(...)`; state stores the `BaseException` (NOT a flattened string);
UI renders `error.userMessage`.

Riverpod (Notifier) with a reusable runner mixin:

```dart
mixin AsyncRunner {
  Future<Result<T, BaseException>> run<T>(
    Future<T> Function() action, {
    required String source,          // 'ClassName.method' convention
    FutureOr<void> Function(T)? onSuccess,
    FutureOr<void> Function(BaseException)? onError,
  }) =>
      guard<T>(action, source: source, onSuccess: onSuccess, onError: onError);
}

class ProfileController extends Notifier<ProfileState> with AsyncRunner {
  Future<void> load() async {
    state = state.copyWith(phase: Phase.loading, error: null);
    final res = await run(() => ref.read(profileRepoProvider).fetch(),
        source: 'ProfileController.load');
    state = switch (res) {
      Ok(:final value) => state.copyWith(phase: Phase.loaded, data: value),
      Err(:final error) => state.copyWith(phase: Phase.error, error: error),
    };
  }
}
```

Bloc/Cubit:

```dart
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit(this._repo) : super(const ProfileState.initial());
  final ProfileRepository _repo;

  Future<void> load() async {
    emit(const ProfileState.loading());
    final res = await guard(() => _repo.fetch(), source: 'ProfileCubit.load');
    res.match(
      ok: (p) => emit(ProfileState.loaded(p)),
      err: (e) => emit(ProfileState.error(e)), // BaseException in state
    );
  }
}
```

State class stores the exception, UI decides presentation:

```dart
sealed class ProfileState {
  const factory ProfileState.error(BaseException error) = ProfileError;
}
// UI: Text(state.error.userMessage); details behind kDebugMode.
```

Known anti-patterns observed in production (what code review should catch):
- `String? errorMessage` in state containers, set from `e.userMessage`, discarding
  type/metadata/severity (blocks retry logic and error-specific UX).
- Riverpod's `AsyncValue.guard` used where bug_handler's `guard` was intended:
  nothing is normalized or reported and no source label exists.
- Repository helpers reimplementing try/catch without reporting, so unexpected
  errors are swallowed before any observer sees them.
- App-local exception hierarchies (`implements Exception`) crossing repository
  boundaries instead of `BaseException` subclasses: severity/user-vs-dev message
  distinctions are lost and the events bypass the reporting pipeline.
