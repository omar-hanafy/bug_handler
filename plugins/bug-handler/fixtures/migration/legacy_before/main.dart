// FIXTURE (legacy 0.0.1-dev.x API) - illustrative only, not analyzed/compiled.
// Shows a typical app bootstrap + feature written against the LEGACY bug_handler
// API. The migrated equivalent lives in ../current_after/.
import 'package:bug_handler/config/config.dart';
import 'package:bug_handler/core/bug_reporter.dart';
import 'package:bug_handler/core/error_handler.dart';
import 'package:bug_handler/ui/error_display_widget.dart';
import 'package:flutter/material.dart';

enum AppEnv { dev, staging, prod }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Legacy: BugReporter owns Sentry (sentryDsn) and wraps app startup.
  await BugReporter.initialize(
    () => runApp(const MyApp()),
    config: ReportConfig(
      sentryDsn: const String.fromEnvironment('SENTRY_DSN'),
      environments: AppEnv.values,
      currentEnvironment: AppEnv.prod,
      minSeverity: ErrorSeverity.warning,
      baseProviders: [],
      onPreSendReport: (report) async {
        // Cancelable pre-send hook: suppress non-reportable events.
        return report.exception.isReportable;
      },
    ),
  );
}

class ProfileController {
  ProfileController(this._repo);
  final ProfileRepository _repo;

  String? errorMessage;
  Profile? profile;

  Future<void> load() async {
    // Legacy: wrapper() returns ReportResult; branching on didThrow/didReport.
    final result = await wrapper<Profile>(
      () => _repo.fetchProfile(),
      source: 'ProfileController.load',
      shouldReport: (e) async => e.severity != ErrorSeverity.info,
      onError: (exception) {
        errorMessage = exception.userMessage;
      },
    );

    if (result.didThrow) {
      if (!result.didReport) {
        // Legacy apps sometimes branched on delivery outcome.
        debugPrint('report was suppressed');
      }
      return;
    }
    profile = result.data;
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Legacy fallback widget with config object.
    return ErrorDisplayWidget(
      config: const ErrorDisplayConfig(
        showErrorDetails: false,
        allowRetry: true,
        allowShare: true,
      ),
      child: const SizedBox.shrink(),
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
