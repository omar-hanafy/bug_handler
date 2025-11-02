import 'dart:math';

import 'package:bug_reporting_system/core/event.dart';
import 'package:bug_reporting_system/reporters/reporter.dart';
import 'package:flutter/foundation.dart';

/// A development reporter that logs event details to the console/debug output.
///
/// Designed for non-production environments. Returns `true` on send for easy pipelines.
class ConsoleReporter extends Reporter {
  /// Creates a console reporter with optional formatting and verbosity controls.
  const ConsoleReporter({
    this.enabled = true,
    this.prettyJson = false,
    this.maxContextKeysPreview = 12,
    this.maxMessageLength = 240,
  });

  /// If false, send() is a no-op that returns false.
  final bool enabled;

  /// Whether to print the entire JSON payload (can be verbose).
  final bool prettyJson;

  /// Maximum number of top-level context keys to preview inline.
  final int maxContextKeysPreview;

  /// Truncate long messages for readability.
  final int maxMessageLength;

  @override
  Future<bool> send(ReportEvent event) async {
    if (!enabled) return false;

    final ex = event.exception;
    final ctxKeys = event.context.keys.take(maxContextKeysPreview).join(', ');
    final msgUser = _truncate(ex.userMessage, maxMessageLength);
    final msgDev = _truncate(ex.devMessage, maxMessageLength);

    debugPrint('────────────────────────────────────────────────────────');
    debugPrint(
        '[BugReport][Console] id=${event.id} ts=${event.timestamp.toIso8601String()}');
    debugPrint('• type=${ex.runtimeType}  severity=${ex.severity}');
    debugPrint('• userMessage: $msgUser');
    debugPrint('• devMessage : $msgDev');
    if (ctxKeys.isNotEmpty) {
      debugPrint(
          '• context    : {$ctxKeys${event.context.length > maxContextKeysPreview ? ', …' : ''}} '
          '(total: ${event.context.length})');
    } else {
      debugPrint('• context    : {}');
    }
    if (ex.stack != null) {
      final top = _firstLines(ex.stack.toString(), 6);
      debugPrint('• stack:\n$top');
    }
    if (prettyJson) {
      // Print full JSON (can be large).
      debugPrint('• json: ${event.toJson()}');
    }
    debugPrint('────────────────────────────────────────────────────────');

    return true;
  }

  String _truncate(String input, int maxLen) {
    if (input.length <= maxLen) return input;
    return '${input.substring(0, max(0, maxLen - 1))}…';
  }

  String _firstLines(String input, int lines) {
    final parts = input.split('\n');
    final take = min(parts.length, lines);
    return parts.take(take).join('\n');
  }
}
