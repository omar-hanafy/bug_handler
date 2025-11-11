import 'dart:convert';

import 'package:bug_handler/core/config.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

/// A compact, typed breadcrumb.
/// Keep payload small; for large blobs prefer attachments or context providers.
class Breadcrumb {
  /// Creates a breadcrumb entry with the given timestamp, message, and metadata.
  const Breadcrumb({
    required this.timestamp,
    required this.message,
    this.data = const {},
  });

  /// Rehydrates a breadcrumb from its serialized map form.
  factory Breadcrumb.fromMap(Map<String, dynamic> map) => Breadcrumb(
        timestamp: DateTime.parse(map['ts'] as String),
        message: map['message'] as String,
        data: (map['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  /// Moment in time when the breadcrumb was recorded.
  final DateTime timestamp;

  /// Human-readable diagnostic message.
  final String message;

  /// Optional structured metadata associated with the breadcrumb.
  final Map<String, dynamic> data;

  /// Serializes the breadcrumb back to a JSON-friendly map.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'ts': timestamp.toIso8601String(),
        'message': message,
        if (data.isNotEmpty) 'data': data,
      };
}

/// Lightweight attachment descriptor (payload sourcing is implementation-defined).
class Attachment {
  /// Creates an attachment descriptor with a display [name] and [contentType].
  const Attachment({
    required this.name,
    required this.contentType,
  });

  /// Rehydrates an attachment from a serialized map.
  factory Attachment.fromMap(Map<String, dynamic> map) => Attachment(
        name: map['name'] as String,
        contentType: map['contentType'] as String,
      );

  /// Human-readable attachment name.
  final String name;

  /// Mime type describing the attachment payload.
  final String contentType;

  /// Serializes the attachment to a JSON-friendly map.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'name': name,
        'contentType': contentType,
      };
}

/// Canonical, serializable error event.
/// This object is immutable; sanitized payload can be embedded via [withPayload].
class ReportEvent {
  /// Constructs an immutable report event with optional initial payload.
  const ReportEvent({
    required this.id,
    required this.exception,
    required this.context,
    required this.timestamp,
    this.fingerprints = const [],
    this.breadcrumbs = const [],
    this.attachments = const [],
    this.handled = true,
    Map<String, dynamic>? payload,
  }) : _payload = payload;

  // ---- deserialization helpers for outbox ----

  /// Recreates a [ReportEvent] from a JSON string.
  factory ReportEvent.fromJson(String json) =>
      ReportEvent.fromMap(jsonDecode(json) as Map<String, dynamic>);

  /// Rehydrates a [ReportEvent] from its map representation.
  factory ReportEvent.fromMap(Map<String, dynamic> map) {
    final ex = map['exception'] as Map<String, dynamic>?;

    final exception = ex != null
        ? SerializedException.fromMap(ex)
        : SerializedException(
            userMessage: 'Unknown error',
            devMessage: 'Unknown error',
          );

    return ReportEvent(
      id: map['id'] as String,
      exception: exception,
      context: (map['context'] as Map?)?.cast<String, dynamic>() ?? const {},
      timestamp: DateTime.parse(map['timestamp'] as String),
      fingerprints: (map['fingerprints'] as List?)?.cast<String>() ?? const [],
      breadcrumbs: (map['breadcrumbs'] as List?)
              ?.cast<Map<dynamic, dynamic>>()
              .map((m) => Breadcrumb.fromMap(m.cast<String, dynamic>()))
              .toList() ??
          const [],
      attachments: (map['attachments'] as List?)
              ?.cast<Map<dynamic, dynamic>>()
              .map((m) => Attachment.fromMap(m.cast<String, dynamic>()))
              .toList() ??
          const [],
      handled: (map['handled'] as bool?) ?? true,
      // Preserve the given map as the payload (already sanitized when read from outbox).
      payload: Map<String, dynamic>.from(map),
    );
  }

  /// Stable identifier for the event.
  final String id;

  /// The captured exception details.
  final BaseException exception;

  /// Structured diagnostic context gathered for the event.
  final Map<String, dynamic> context;

  /// Timestamp for when the event was created.
  final DateTime timestamp;

  /// Fingerprint hints used for deduplication and grouping.
  final List<String> fingerprints;

  /// Breadcrumbs leading up to the event.
  final List<Breadcrumb> breadcrumbs;

  /// Attachments associated with the event.
  final List<Attachment> attachments;

  /// Whether the error was handled (caught) at the call site.
  final bool handled;

  /// An optional pre-sanitized payload (serialized form).
  final Map<String, dynamic>? _payload;

  /// Generates a monotonically increasing string ID.
  static String generateId() {
    final now = DateTime.now().toUtc();
    final micros = now.microsecondsSinceEpoch;
    return 'r_${micros.toRadixString(36)}';
  }

  /// Returns the serialized map (prefer sanitized payload when present).
  Map<String, dynamic> toMap() =>
      _payload ??
      <String, dynamic>{
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'handled': handled,
        'exception': <String, dynamic>{
          'type': exception.runtimeType.toString(),
          'userMessage': exception.userMessage,
          'devMessage': exception.devMessage,
          'severity': exception.severity.name,
          'metadata': exception.metadata,
          if (exception.cause != null) 'cause': exception.cause.toString(),
          if (exception.stack != null) 'stack': exception.stack.toString(),
        },
        'context': context,
        if (fingerprints.isNotEmpty) 'fingerprints': fingerprints,
        if (breadcrumbs.isNotEmpty)
          'breadcrumbs': breadcrumbs.map((b) => b.toMap()).toList(),
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toMap()).toList(),
      };

  /// Serializes the event to a JSON string.
  String toJson() => jsonEncode(toMap());

  /// Returns a copy of the event with updated fields.
  ReportEvent copyWith({
    String? id,
    BaseException? exception,
    Map<String, dynamic>? context,
    DateTime? timestamp,
    List<String>? fingerprints,
    List<Breadcrumb>? breadcrumbs,
    List<Attachment>? attachments,
    bool? handled,
  }) {
    return ReportEvent(
      id: id ?? this.id,
      exception: exception ?? this.exception,
      context: context ?? this.context,
      timestamp: timestamp ?? this.timestamp,
      fingerprints: fingerprints ?? this.fingerprints,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      attachments: attachments ?? this.attachments,
      handled: handled ?? this.handled,
      payload: _payload,
    );
  }

  /// Returns a copy embedding a pre-sanitized payload.
  ReportEvent withPayload(Map<String, dynamic> payload) => ReportEvent(
        id: id,
        exception: exception,
        context: context,
        timestamp: timestamp,
        fingerprints: fingerprints,
        breadcrumbs: breadcrumbs,
        attachments: attachments,
        handled: handled,
        payload: payload,
      );
}

/// A generic, serializable exception used when reconstructing events from JSON.
/// This allows outbox -> pipeline replay without requiring the original subtype.
class SerializedException extends BaseException {
  /// Creates a serializable wrapper around exception details.
  SerializedException({
    required super.userMessage,
    required super.devMessage,
    super.cause,
    super.stack,
    super.metadata = const {},
    super.severity = Severity.error,
    super.isReportable = true,
  });

  /// Rehydrates a serialized exception from a JSON map.
  factory SerializedException.fromMap(Map<String, dynamic> map) {
    final causeStr = map['cause'] as String?;
    final stackStr = map['stack'] as String?;
    final sevName = map['severity'] as String? ?? 'error';

    return SerializedException(
      userMessage: (map['userMessage'] as String?) ?? 'An error occurred',
      devMessage: (map['devMessage'] as String?) ?? 'Unknown error',
      cause: causeStr,
      stack: stackStr != null ? StackTrace.fromString(stackStr) : null,
      metadata: (map['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      severity: Severity.values.firstWhere(
        (s) => s.name == sevName,
        orElse: () => Severity.error,
      ),
    );
  }
}
