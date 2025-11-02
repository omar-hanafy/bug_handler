import 'package:bug_reporting_system/core/config.dart' show Severity;
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:flutter/foundation.dart';

/// Exception type that wraps a [FlutterErrorDetails] produced by the
/// Flutter framework (build/layout/paint, etc.).
///
/// Use this when wiring global handlers (e.g., in `BugReportBindings`) to
/// transform framework errors into your domain exception type.
class FlutterErrorException extends BaseException {
  /// Wraps [FlutterErrorDetails] so it can flow through the reporting pipeline.
  FlutterErrorException(
    this.details, {
    Severity? severityOverride,
    String? userMessage,
    String? devMessage,
  }) : super(
          userMessage:
              userMessage ?? 'An unexpected error occurred in the application',
          devMessage: devMessage ??
              'Flutter framework error: ${_describeException(details)}',
          cause: details.exception,
          stack: details.stack,
          severity: severityOverride ?? Severity.error,
          metadata: _buildMetadata(details),
        );

  /// The original Flutter framework error details.
  final FlutterErrorDetails details;

  /// Convenience accessor for the source library, if provided.
  String get library => details.library ?? 'flutter';

  /// Convenience accessor for the framework context node (may be null).
  DiagnosticsNode? get contextNode => details.context;

  @override
  String toString() {
    final ctxDesc = contextNode?.toDescription() ?? 'n/a';
    return '''
${kDebugMode ? runtimeType : ''}
  Library     : $library
  Context     : $ctxDesc
  User Message: $userMessage
  Dev Message : $devMessage
${stack != null ? '  Stack      : $stack' : ''}
''';
  }

  // ====================== Internals ======================

  static String _describeException(FlutterErrorDetails d) {
    final type = d.exception.runtimeType.toString();
    final msg = d.exception.toString();
    // Keep short & actionable; Sentry/Crashlytics receive full stack anyway.
    return '$type: $msg';
  }

  static Map<String, dynamic> _buildMetadata(FlutterErrorDetails d) {
    return <String, dynamic>{
      'flutter': {
        'library': d.library,
        'silent': d.silent == true,
        'summary': _safeSummary(d),
        'context': _contextToMap(d.context),
        'information': _collectInformation(d),
      },
      'exception': {
        'type': d.exception.runtimeType.toString(),
        'toString': d.exception.toString(),
      },
      if (d.stack != null) 'stackTraceString': d.stack.toString(),
    };
  }

  static String? _safeSummary(FlutterErrorDetails d) {
    // Some Flutter versions expose toStringShort/summary differently.
    try {
      final short = d.toStringShort();
      if (short.isNotEmpty) return short;
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic>? _contextToMap(DiagnosticsNode? node) {
    if (node == null) return null;
    try {
      return <String, dynamic>{
        'name': node.name,
        'description': node.toDescription(),
        'level': node.level.toString(),
        'style': node.style?.toString(),
        'showName': node.showName,
        'allowWrap': node.allowWrap,
        'allowNameWrap': node.allowNameWrap,
        'allowTruncate': node.allowTruncate,
        'value': node.value?.toString(),
      };
    } catch (_) {
      // Be defensive: context formatting differences shouldn't break reporting.
      return <String, dynamic>{'description': node.toString()};
    }
  }

  static List<Map<String, String>> _collectInformation(FlutterErrorDetails d) {
    final collector = d.informationCollector;
    if (collector == null) return const [];

    try {
      final nodes = collector();
      return nodes
          .map((n) => <String, String>{
                'name': n.name ?? '',
                'description': n.toDescription(),
              })
          .toList(growable: false);
    } catch (_) {
      // Fall back to a single bucket with raw text if something goes sideways.
      return const [
        {'description': 'Failed to collect additional FlutterError information'}
      ];
    }
  }
}
