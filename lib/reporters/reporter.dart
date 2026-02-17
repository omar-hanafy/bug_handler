import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/report.dart';

/// Base abstract class for report sending implementations
abstract class Reporter {
  const Reporter();

  /// Send report through the reporting system
  Future<bool> sendReport(Report report);

  /// Share report manually (e.g., as a file)
  Future<bool> shareReport(Report report);

  /// Generate a report file
  @protected
  Future<File> generateReportFile(Report report) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String();
    final path = '${directory.path}/bug_report_$timestamp.json';

    final file = File(path);
    try {
      // Pretty print JSON for readability
      return file.writeAsString(report.toJson());
    } catch (_) {
      // Fallback to basic toString if JSON fails
      return file.writeAsString(report.toString());
    }
  }

  /// Generate a unique report identifier
  @protected
  String generateReportId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.toString() + DateTime.now().microsecond.toString();
    return 'report_$random';
  }
}
