import 'dart:io';

import 'package:bug_handler/core/event.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

/// Base contract for delivering [ReportEvent]s to one or more destinations.
///
/// Implementations should be resilient and never throw; return `false` on
/// delivery failure so the pipeline can fallback (e.g., queue to outbox).
abstract class Reporter {
  /// Const constructor to support lightweight subclasses.
  const Reporter();

  /// Sends a [ReportEvent] to the remote/system of choice.
  ///
  /// Returns `true` iff the event was successfully delivered.
  Future<bool> send(ReportEvent event);

  /// User-initiated sharing of a [ReportEvent] (e.g., via share sheet).
  ///
  /// Default is a no-op; override in reporters that support manual sharing.
  Future<bool> share(ReportEvent event) async => false;

  /// Generates a JSON file representation of the [event] for sharing or local persistence.
  ///
  /// The file name will be derived from the event id and timestamp unless
  /// [fileName] is provided. The file will be created in [directory] if supplied,
  /// otherwise the platform's temporary directory is used.
  @protected
  Future<File> generateFile(
    ReportEvent event, {
    String? fileName,
    Directory? directory,
  }) async {
    final dir = directory ?? await getTemporaryDirectory();
    final name = (fileName?.trim().isNotEmpty ?? false)
        ? _sanitizeFileComponent(fileName!.trim())
        : _defaultFileName(event);

    final path = '${dir.path}${Platform.pathSeparator}$name';
    final file = File(path);

    // Use the event's own JSON encoder to preserve consistent shape/ordering.
    final contents = event.toJson();

    // Ensure parent directory exists.
    await file.parent.create(recursive: true);
    return file.writeAsString(contents, flush: true);
  }

  /// Builds a stable, human-readable file name for a report event.
  @protected
  String defaultFileName(ReportEvent event) => _defaultFileName(event);

  String _defaultFileName(ReportEvent event) {
    final ts = event.timestamp
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '');
    final base = 'bug_report_${event.id}_$ts.json';
    return _sanitizeFileComponent(base);
  }

  String _sanitizeFileComponent(String input) {
    // Replace characters that are generally unsafe for file names across platforms.
    const invalid = r'<>:"/\|?*';
    final sanitized =
        input.split('').map((c) => invalid.contains(c) ? '_' : c).join();
    // Guard against empty or extension-less artifacts.
    return sanitized.endsWith('.json') ? sanitized : '$sanitized.json';
  }
}
