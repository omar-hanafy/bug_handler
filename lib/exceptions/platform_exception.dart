import 'package:bug_reporting_system/core/config.dart' show Severity;
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:meta/meta.dart';

/// Base exception for platform channel/OS operation failures.
@immutable
class PlatformOperationException extends BaseException {
  /// Creates a platform exception describing the failed [operation].
  PlatformOperationException({
    required this.operation,
    required super.userMessage,
    required super.devMessage,
    this.code,
    this.details,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity,
    super.isReportable,
  }) : super(
          metadata: {
            'operation': operation,
            if (code != null) 'code': code,
            if (details != null) 'details': details,
            ...metadata,
          },
        );

  /// Creates a [PlatformOperationException] from a [PlatformException].
  factory PlatformOperationException.fromPlatformException(
    PlatformException e, {
    required String operation,
    String? userMessage,
    String? devMessage,
    bool isReportable = true,
    Severity? severity,
  }) {
    final s = severity ?? _severityFromCode(e.code);
    return PlatformOperationException(
      operation: operation,
      userMessage: userMessage ?? _userMessageFromCode(e.code),
      devMessage: devMessage ?? (e.message ?? 'Unknown platform error.'),
      code: e.code,
      details: e.details,
      cause: e,
      severity: s,
      isReportable: isReportable,
    );
  }

  /// Logical operation name (e.g., "camera_capture").
  final String operation;

  /// Platform-specific error code, when provided by the channel.
  final String? code;

  /// Additional details supplied by the platform.
  final dynamic details;

  /// Indicates whether the platform error represents a timeout.
  bool get isTimeout => (code ?? '').toLowerCase().contains('timeout');

  /// Indicates whether the platform error stems from a permission issue.
  bool get isPermissionError =>
      (code ?? '').toLowerCase().contains('permission');

  static Severity _severityFromCode(String code) {
    final c = code.toLowerCase();
    if (c.contains('permission')) return Severity.warning;
    if (c.contains('timeout')) return Severity.warning;
    if (c.contains('unavailable')) return Severity.error;
    if (c.contains('invalid')) return Severity.warning;
    return Severity.error;
  }

  static String _userMessageFromCode(String code) {
    final c = code.toLowerCase();
    if (c.contains('permission')) {
      return 'Permission denied for this operation.';
    }
    if (c.contains('timeout')) {
      return 'Operation timed out. Please try again.';
    }
    if (c.contains('unavailable')) {
      return 'This feature is currently unavailable.';
    }
    if (c.contains('invalid')) {
      return 'Invalid request for this operation.';
    }
    return 'Operation failed.';
  }
}

/// Media-specific operation failures (pick/upload/download/process).
@immutable
class MediaException extends PlatformOperationException {
  /// Creates a media exception scoped to the given [type] and [mediaType].
  MediaException({
    required MediaOperationType type,
    required this.mediaType,
    String? path,
    String? mimeType,
    int? fileSize,
    super.code,
    super.details,
    super.cause,
    super.stack,
    bool isRetryable = true,
    super.isReportable,
  }) : super(
          operation: 'media_${type.name}',
          userMessage: _userMessage(type),
          devMessage: _devMessage(type, path),
          severity: _severity(type),
          metadata: {
            'mediaOperation': type.name,
            'mediaType': mediaType,
            if (path != null) 'path': path,
            if (mimeType != null) 'mimeType': mimeType,
            if (fileSize != null) 'fileSize': fileSize,
            'isRetryable': isRetryable,
          },
        );

  /// Category of media that was being processed (e.g. `image`).
  final String mediaType; // e.g. 'image', 'video', 'audio'

  static String _userMessage(MediaOperationType t) {
    switch (t) {
      case MediaOperationType.upload:
        return 'Failed to upload media.';
      case MediaOperationType.download:
        return 'Failed to download media.';
      case MediaOperationType.picker:
        return 'Failed to select media.';
      case MediaOperationType.processing:
        return 'Failed to process media.';
      case MediaOperationType.permission:
        return 'Media permission denied.';
      case MediaOperationType.format:
        return 'Unsupported media format.';
      case MediaOperationType.size:
        return 'Media file too large.';
    }
  }

  static String _devMessage(MediaOperationType t, String? path) {
    final location = path != null ? ' at $path' : '';
    return 'Media operation ${t.name} failed$location.';
  }

  static Severity _severity(MediaOperationType t) {
    switch (t) {
      case MediaOperationType.permission:
      case MediaOperationType.format:
      case MediaOperationType.size:
        return Severity.warning;
      case MediaOperationType.upload:
      case MediaOperationType.download:
      case MediaOperationType.picker:
      case MediaOperationType.processing:
        return Severity.error;
    }
  }
}

/// Types of media operations supported by [MediaException].
enum MediaOperationType {
  /// Uploading media to a remote target failed.
  upload,

  /// Downloading media from a remote target failed.
  download,

  /// Selecting media (picker) failed.
  picker,

  /// Post-processing of media (encode/resize/etc.) failed.
  processing,

  /// Permission to access media was denied.
  permission,

  /// Media format was unsupported or invalid.
  format,

  /// Media exceeded configured size limits.
  size,
}
