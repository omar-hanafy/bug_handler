import 'package:bug_reporting_system/core/config.dart' show Severity;
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:meta/meta.dart';

/// Navigation and routing related failures.
@immutable
class NavigationException extends BaseException {
  /// Creates a navigation exception, capturing the failed [operation] and [route].
  NavigationException({
    required this.route,
    required this.operation,
    this.arguments,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic> metadata = const {},
    super.severity = Severity.warning,
    super.isReportable = false,
  }) : super(
          userMessage: userMessage ?? 'Navigation failed.',
          devMessage: devMessage ?? 'Navigation failed: $operation to $route',
          metadata: {
            'route': route,
            'operation': operation,
            if (arguments != null) 'arguments': arguments,
            ...metadata,
          },
        );

  /// Target route name.
  final String route;

  /// Navigation operation that was attempted (`push`, `pop`, etc.).
  final String operation;

  /// Arguments passed to the navigation call.
  final Object? arguments;
}

/// Raised when navigation targets an unknown route name.
@immutable
class RouteNotFoundException extends NavigationException {
  /// Creates an exception indicating the requested [route] could not be resolved.
  RouteNotFoundException({
    required super.route,
    super.arguments,
    super.cause,
    super.stack,
    super.metadata,
  }) : super(
          operation: 'push',
          userMessage: 'Page not found.',
          devMessage: 'Route not found: $route',
          severity: Severity.warning,
          isReportable: false,
        );
}

/// Raised when supplied navigation arguments fail validation.
@immutable
class InvalidRouteArgumentsException extends NavigationException {
  /// Creates an exception signaling invalid [arguments] for the given [route].
  InvalidRouteArgumentsException({
    required super.route,
    required Object super.arguments,
    super.cause,
    super.stack,
    super.metadata,
  }) : super(
          operation: 'push',
          userMessage: 'Invalid navigation parameters.',
          devMessage: 'Invalid arguments for route: $route',
          severity: Severity.warning,
          isReportable: false,
        );
}
