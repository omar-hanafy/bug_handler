import 'package:bug_reporting_system/core/config.dart' show Severity;
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Generic permission state mapping independent of a specific plugin.
/// Map your platform/plugin-specific statuses to this enum at the boundary.
enum PermissionStatus {
  /// User denied the permission but can be prompted again.
  denied,

  /// Permission is permanently denied; system dialog will not reappear.
  permanentlyDenied,

  /// Permission is restricted by parental controls or device policy.
  restricted,

  /// Permission is granted with reduced capabilities.
  limited,

  /// Permission is provisionally granted pending user confirmation.
  provisional,

  /// Permission is fully granted.
  granted,
}

/// Permission-related failures (camera, location, notifications, etc.).
@immutable
class PermissionException extends BaseException {
  /// Creates a permission exception describing the failed [permission] and [status].
  PermissionException({
    required this.permission,
    required this.status,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.isReportable = false,
  }) : super(
          userMessage: userMessage ?? _defaultUserMessage(permission, status),
          devMessage: devMessage ?? 'Permission denied: $permission ($status).',
          severity: _severity(status),
          metadata: {
            'permission': permission,
            'status': status.name,
            ...metadata,
          },
        );

  /// Identifier describing the missing permission (e.g. "camera").
  final String permission;

  /// Normalized permission status.
  final PermissionStatus status;

  static Severity _severity(PermissionStatus s) {
    switch (s) {
      case PermissionStatus.permanentlyDenied:
      case PermissionStatus.restricted:
        return Severity.error;
      case PermissionStatus.denied:
      case PermissionStatus.limited:
      case PermissionStatus.provisional:
        return Severity.warning;
      case PermissionStatus.granted:
        return Severity.info;
    }
  }

  static String _defaultUserMessage(String permission, PermissionStatus s) {
    switch (s) {
      case PermissionStatus.denied:
        return 'Please grant $permission permission to use this feature.';
      case PermissionStatus.permanentlyDenied:
        return 'Permission for $permission was permanently denied. Enable it in Settings.';
      case PermissionStatus.restricted:
        return '$permission access is restricted on this device.';
      case PermissionStatus.limited:
        return '$permission access is limited. Adjust your settings to proceed.';
      case PermissionStatus.provisional:
        return '$permission permission is provisional and may require confirmation.';
      case PermissionStatus.granted:
        return '$permission permission granted.';
    }
  }
}
