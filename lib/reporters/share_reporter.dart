import 'package:bug_handler/core/event.dart';
import 'package:bug_handler/reporters/reporter.dart';
import 'package:share_plus/share_plus.dart';

/// Reporter that shares events via the platform share sheet.
///
/// Useful for user-initiated reports or as a fallback when network delivery fails.
/// By default, `send()` delegates to `share()` so it is safe to include this
/// reporter in a pipeline even when automatic sending occurs.
class ShareReporter extends Reporter {
  /// Creates a share reporter with optional customization hooks for text and filenames.
  const ShareReporter({
    this.subjectPrefix = 'Bug Report',
    this.textBuilder,
    this.fileNameBuilder,
  });

  /// Subject prefix displayed in the share sheet (email clients, etc.).
  final String subjectPrefix;

  /// Optional share body builder. If null, a compact default is used.
  final String Function(ReportEvent event)? textBuilder;

  /// Optional custom file name builder. If null, [Reporter.defaultFileName] is used.
  final String Function(ReportEvent event)? fileNameBuilder;

  @override
  Future<bool> send(ReportEvent event) async {
    // Treat "send" as "share" for this reporter; there is no remote target.
    return share(event);
  }

  @override
  Future<bool> share(ReportEvent event) async {
    try {
      final name = fileNameBuilder?.call(event) ?? defaultFileName(event);
      final file = await generateFile(event, fileName: name);

      final subject = _buildSubject(event);
      final body = textBuilder?.call(event) ?? _defaultBody(event);

      // Updated line:
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: subject,
          text: body,
          // Use fileNameOverrides for robustness, as the `name`
          // property on XFile constructor is not always respected.
          fileNameOverrides: [name],
        ),
      );
      return true;
    } catch (_) {
      // Nothing more we can do if the system share fails.
      return false;
    }
  }

  String _buildSubject(ReportEvent event) {
    final type = event.exception.runtimeType.toString();
    final sev = event.exception.severity.toString();
    return '$subjectPrefix • ${event.id} • $type • $sev';
  }

  String _defaultBody(ReportEvent event) {
    final ex = event.exception;
    final parts = <String>[
      'A bug report has been generated.',
      'ID: ${event.id}',
      'When: ${event.timestamp.toIso8601String()}',
      'Type: ${ex.runtimeType}',
      'Severity: ${ex.severity}',
      if (ex.userMessage.isNotEmpty) 'User Message: ${ex.userMessage}',
      if (ex.devMessage.isNotEmpty) 'Dev Message: ${ex.devMessage}',
      'The full JSON payload is attached as ${defaultFileName(event)}.',
    ];
    return parts.join('\n');
  }
}
