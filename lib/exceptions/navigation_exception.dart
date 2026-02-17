import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/exceptions/base_exception.dart';

class NavigationException extends BaseException {
  NavigationException({
    required this.route,
    required this.operation,
    this.arguments,
    String? userMessage,
    String? devMessage,
    super.cause,
    super.stack,
    Map<String, dynamic>? additionalMetadata,
  }) : super(
         userMessage: userMessage ?? 'Navigation failed',
         devMessage: devMessage ?? 'Navigation failed: $operation to $route',
         severity: ErrorSeverity.warning,
         metadata: {
           'route': route,
           'operation': operation,
           if (arguments != null) 'arguments': arguments.toString(),
           ...?additionalMetadata,
         },
       );

  final String route;
  final String operation;
  final Object? arguments;
}

class RouteNotFoundException extends NavigationException {
  RouteNotFoundException({
    required super.route,
    super.arguments,
    super.cause,
    super.stack,
  }) : super(
         operation: 'push',
         userMessage: 'Page not found',
         devMessage: 'Route not found: $route',
       );
}

class InvalidRouteArgumentsException extends NavigationException {
  InvalidRouteArgumentsException({
    required super.route,
    required Object super.arguments,
    super.cause,
    super.stack,
  }) : super(
         operation: 'push',
         userMessage: 'Invalid navigation parameters',
         devMessage: 'Invalid arguments for route: $route',
       );
}
