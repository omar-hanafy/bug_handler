import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

class StorageException extends BaseException {
  StorageException({
    required super.userMessage,
    required super.devMessage,
    required this.operation,
    this.key,
    this.storageType,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
  }) : super(
         severity: ErrorSeverity.error,
         metadata: {
           'operation': operation,
           if (key != null) 'key': key,
           if (storageType != null) 'storageType': storageType,
           ...?additionalMetadata,
         },
       );

  final String operation;
  final String? key;
  final String? storageType;
}

class CacheException extends StorageException {
  CacheException({
    required String super.key,
    required super.operation,
    super.cause,
    super.stack,
  }) : super(
         userMessage: 'Failed to access cached data',
         devMessage: 'Cache operation failed: $operation for key: $key',
         storageType: 'cache',
       );
}

class SecureStorageException extends StorageException {
  SecureStorageException({
    required String super.key,
    required super.operation,
    super.cause,
    super.stack,
  }) : super(
         userMessage: 'Failed to access secure storage',
         devMessage:
             'Secure storage operation failed: $operation for key: $key',
         storageType: 'secure_storage',
       );
}
