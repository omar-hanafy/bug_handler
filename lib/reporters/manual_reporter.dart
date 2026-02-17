// manual_reporter.dart
import 'package:bug_handler/core/report.dart';
import 'package:bug_handler/reporters/reporter.dart';
import 'package:share_plus/share_plus.dart';

/// Reporter implementation for manual sharing of reports
class ManualReporter extends Reporter {
  @override
  Future<bool> sendReport(Report report) async {
    // Manual reporter always defaults to sharing
    return shareReport(report);
  }

  @override
  Future<bool> shareReport(Report report) async {
    try {
      final file = await generateReportFile(report);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Bug Report',
        text: 'Error log attached.',
      );
      return true;
    } catch (_) {
      // If sharing fails, we can't do much
      // Could log to console in debug mode
      return false;
    }
  }
}
