import 'package:bug_reporting_system/core/config.dart' show Severity;
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Storage and caching layer failures.
@immutable
class StorageException extends BaseException {
  /// Creates a storage exception describing the failed [operation] and optional [key].
  StorageException({
    required super.userMessage,
    required super.devMessage,
    required this.operation,
    this.key,
    this.storageType,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity,
    super.isReportable,
  }) : super(
          metadata: {
            'operation': operation,
            if (key != null) 'key': key,
            if (storageType != null) 'storageType': storageType,
            ...metadata,
          },
        );

  /// Operation that failed (e.g., `read`, `write`).
  final String operation;

  /// Storage key involved in the failure.
  final String? key;

  /// Storage backend type (cache, secure storage, etc.).
  final String? storageType;
}

/// Cache-layer storage failures.
@immutable
class CacheException extends StorageException {
  /// Creates a cache exception for failures interacting with in-memory/disk cache.
  CacheException({
    required String super.key,
    required super.operation,
    super.cause,
    super.stack,
    super.metadata,
  }) : super(
          userMessage: 'Failed to access cached data.',
          devMessage: 'Cache operation failed: $operation for key: $key',
          storageType: 'cache',
          severity: Severity.error,
          isReportable: true,
        );
}

/// Secure storage (keychain/keystore) failures.
@immutable
class SecureStorageException extends StorageException {
  /// Creates a secure storage exception for failures accessing encrypted stores.
  SecureStorageException({
    required String super.key,
    required super.operation,
    super.cause,
    super.stack,
    super.metadata,
  }) : super(
          userMessage: 'Failed to access secure storage.',
          devMessage:
              'Secure storage operation failed: $operation for key: $key',
          storageType: 'secure_storage',
          severity: Severity.error,
          isReportable: true,
        );
}
