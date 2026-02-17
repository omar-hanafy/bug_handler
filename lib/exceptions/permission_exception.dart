import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

class PermissionException extends BaseException {
  PermissionException({
    required this.permission,
    required this.status,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
  }) : super(
         userMessage: userMessage ?? _getDefaultUserMessage(permission, status),
         devMessage: devMessage ?? 'Permission denied: $permission ($status)',
         severity: _getSeverity(status),
         metadata: {
           'permission': permission,
           'status': status.name,
           ...?additionalMetadata,
         },
       );

  final String permission;
  final PermissionStatus status;

  static String _getDefaultUserMessage(
    String permission,
    PermissionStatus status,
  ) {
    return switch (status) {
      PermissionStatus.denied =>
        'Please grant $permission permission to use this feature',
      PermissionStatus.permanentlyDenied =>
        'Permission for $permission was permanently denied. Please enable it in settings',
      PermissionStatus.restricted =>
        '$permission access is restricted on this device',
      _ => 'Unable to access $permission',
    };
  }

  static ErrorSeverity _getSeverity(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.permanentlyDenied => ErrorSeverity.error,
      PermissionStatus.restricted => ErrorSeverity.error,
      _ => ErrorSeverity.warning,
    };
  }
}

enum PermissionStatus {
  denied,
  permanentlyDenied,
  restricted,
  limited,
  provisional,
}
