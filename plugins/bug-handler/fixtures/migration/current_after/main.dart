// FIXTURE (current 1.0.0-dev.x API) - illustrative only, not analyzed/compiled.
// The ../legacy_before/main.dart bootstrap + feature, migrated to the CURRENT
// bug_handler API. Comments mark each mapping decision.
import 'package:bug_handler/bug_handler.dart';
import 'package:bug_handler/flutter/bindings.dart'; // not exported by main entrypoint
import 'package:bug_handler/flutter/error_boundary.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart'; // now an explicit app dependency

enum AppEnv { dev, staging, prod }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sentry is app-owned now (legacy sentryDsn is gone). Transport-only:
  // remove Sentry's own error hook so bug_handler stays the single capturer.
  const dsn = String.fromEnvironment('SENTRY_DSN');
  if (dsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options
        ..dsn = dsn
        ..environment = AppEnv.prod.name;
      options.integrations.removeWhere((i) => i is OnErrorIntegration);
    });
  }

  await BugReportBindings.runAppWithReporting(
    app: () => const MyApp(),
    config: ClientConfig(
      // enum currentEnvironment -> String; allow-list moved into Policy.
      environment: AppEnv.prod.name,
      policy: const Policy(
        minSeverity:
            Severity.warning, // ErrorSeverity -> Severity (typedef also ok)
        environments: {'dev', 'staging', 'prod'},
      ),
      baseProviders: [AppContextProvider(), DeviceContextProvider()],
      sanitizers: [DefaultSanitizer()],
      reporters: [
        if (dsn.isNotEmpty) const SentryReporter(),
      ],
    ),
  );
}

/// onPreSendReport(isReportable) had no direct equivalent: the current pipeline
/// does NOT enforce isReportable, so the suppression moved INTO the reporter
/// (skip -> return true so nothing is re-queued to the outbox).
class SentryReporter extends Reporter {
  const SentryReporter();

  @override
  Future<bool> send(ReportEvent event) async {
    if (!event.exception.isReportable) return true; // intentional skip
    if (event.exception.severity == Severity.info)
      return true; // old shouldReport
    try {
      await Sentry.captureEvent(SentryEvent(
        message: SentryMessage(event.exception.devMessage),
        fingerprint: event.fingerprints,
        extra: event.toMap(), // sanitized payload, never event.context
      ));
      return true;
    } catch (_) {
      return false; // genuine failure -> outbox retry
    }
  }
}

class ProfileController {
  ProfileController(this._repo);
  final ProfileRepository _repo;

  // String errorMessage -> the typed exception (UI renders userMessage).
  BaseException? error;
  Profile? profile;

  Future<void> load() async {
    // wrapper()/ReportResult -> guard()/Result. shouldReport moved to reporter.
    final res = await guard<Profile>(
      () => _repo.fetchProfile(),
      source: 'ProfileController.load',
    );
    switch (res) {
      case Ok(:final value):
        profile = value;
        error = null;
      case Err(:final error):
        // didReport branch DELETED: delivery outcome is intentionally not
        // exposed; app logic must not depend on it.
        this.error = error;
    }
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ErrorDisplayWidget(config:) -> ErrorBoundary (default fallback already
    // provides Retry + Report; customize via fallbackBuilder if needed).
    return const ErrorBoundary(
      showDetails: false,
      child: SizedBox.shrink(),
    );
  }
}

// --- stubs so the fixture reads standalone ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp();
}

class Profile {}

class ProfileRepository {
  Future<Profile> fetchProfile() async => Profile();
}
