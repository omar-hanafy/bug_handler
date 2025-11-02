import 'package:bug_reporting_system/core/config.dart' show Severity;
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Failures during setup/bootstrap of critical components.
@immutable
class InitializationException extends BaseException {
  /// Creates an initialization exception scoped to a specific [component].
  InitializationException({
    required String component,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.isReportable,
  }) : super(
          userMessage:
              userMessage ?? 'Failed to initialize the application component.',
          devMessage: devMessage ?? 'Initialization failed for: $component',
          severity: Severity.critical,
          metadata: {
            'component': component,
            ...metadata,
          },
        );
}

/// Thrown when a required component is used before being initialized.
@immutable
class ComponentNotInitializedException extends InitializationException {
  /// Creates an exception indicating the referenced component has not been initialized.
  ComponentNotInitializedException({
    required super.component,
    super.cause,
    super.stack,
    super.metadata,
    super.isReportable,
  }) : super(
          userMessage: 'Application setup is incomplete.',
          devMessage: '$component is not initialized.',
        );
}
