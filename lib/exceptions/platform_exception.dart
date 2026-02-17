import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:flutter/services.dart';

/// Base class for platform-specific operation exceptions
class PlatformOperationException extends BaseException {
  PlatformOperationException({
    required this.operation,
    required super.userMessage,
    required super.devMessage,
    this.code,
    this.details,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
    super.severity,
    bool isRetryable = false,
  }) : super(
         metadata: {
           'operation': operation,
           'isRetryable': isRetryable,
           if (code != null) 'code': code,
           if (details != null) 'details': details,
           ...?additionalMetadata,
         },
       );

  /// Creates a PlatformOperationException from a PlatformException
  factory PlatformOperationException.fromPlatformException(
    PlatformException e, {
    required String operation,
    String? userMessage,
    String? devMessage,
    bool isRetryable = false,
    ErrorSeverity? severity,
  }) {
    // Determine severity based on error code pattern
    final determinedSeverity = severity ?? _determineSeverityFromCode(e.code);

    return PlatformOperationException(
      operation: operation,
      userMessage: userMessage ?? _getUserMessageFromCode(e.code),
      devMessage: devMessage ?? e.message ?? 'Unknown platform error',
      code: e.code,
      details: e.details,
      cause: e,
      severity: determinedSeverity,
      isRetryable: isRetryable,
    );
  }

  final String operation;
  final String? code;
  final dynamic details;

  /// Determines if this exception represents a timeout
  bool get isTimeout => code?.toLowerCase().contains('timeout') ?? false;

  /// Determines if this exception represents a permission error
  bool get isPermissionError =>
      code?.toLowerCase().contains('permission') ?? false;

  static ErrorSeverity _determineSeverityFromCode(String code) {
    final lowerCode = code.toLowerCase();
    if (lowerCode.contains('permission')) return ErrorSeverity.warning;
    if (lowerCode.contains('timeout')) return ErrorSeverity.warning;
    if (lowerCode.contains('unavailable')) return ErrorSeverity.error;
    if (lowerCode.contains('invalid')) return ErrorSeverity.warning;
    return ErrorSeverity.error;
  }

  static String _getUserMessageFromCode(String code) {
    final lowerCode = code.toLowerCase();
    if (lowerCode.contains('permission')) {
      return 'Permission denied for this operation';
    }
    if (lowerCode.contains('timeout')) {
      return 'Operation timed out. Please try again';
    }
    if (lowerCode.contains('unavailable')) {
      return 'This feature is currently unavailable';
    }
    return 'Operation failed';
  }

  @override
  String toString() =>
      '''
PlatformOperationException: $operation
Code: ${code ?? 'N/A'}
Message: $devMessage
Details: ${details ?? 'N/A'}
${cause != null ? '\nCause: $cause' : ''}
''';
}

/// Specialized exception for media operations
class MediaException extends PlatformOperationException {
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
    super.isRetryable = true,
  }) : super(
         operation: 'media_${type.name}',
         userMessage: _getUserMessage(type),
         devMessage: _getDevMessage(type, path),
         severity: _determineSeverity(type),
         additionalMetadata: {
           'mediaType': type.name,
           'contentType': mediaType,
           if (path != null) 'path': path,
           if (mimeType != null) 'mimeType': mimeType,
           if (fileSize != null) 'fileSize': fileSize,
         },
       );

  final String mediaType; // e.g., 'image', 'video', 'audio'

  static String _getUserMessage(MediaOperationType type) {
    return switch (type) {
      MediaOperationType.upload => 'Failed to upload media',
      MediaOperationType.download => 'Failed to download media',
      MediaOperationType.picker => 'Failed to select media',
      MediaOperationType.processing => 'Failed to process media',
      MediaOperationType.permission => 'Media permission denied',
      MediaOperationType.format => 'Unsupported media format',
      MediaOperationType.size => 'Media file too large',
    };
  }

  static String _getDevMessage(MediaOperationType type, String? path) {
    final location = path != null ? ' at $path' : '';
    return 'Media operation ${type.name} failed$location';
  }

  static ErrorSeverity _determineSeverity(MediaOperationType type) {
    return switch (type) {
      MediaOperationType.permission => ErrorSeverity.warning,
      MediaOperationType.format => ErrorSeverity.warning,
      MediaOperationType.size => ErrorSeverity.warning,
      _ => ErrorSeverity.error,
    };
  }
}

enum MediaOperationType {
  upload,
  download,
  picker,
  processing,
  permission,
  format,
  size,
}
