import 'package:bug_handler/context/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_helper_utils/flutter_helper_utils.dart';

/// Captures a snapshot of UI‑related data that can help reproduce rendering,
/// sizing, and theming issues. Marked as [manualReportOnly] to avoid heavy work
/// during automatic reporting.
class UIContextProvider extends ContextProvider {
  /// Creates a UI context provider bound to the given [BuildContext], with an
  /// optional hook for additional custom fields.
  const UIContextProvider(
    this.context, {
    Map<String, dynamic> Function()? additional,
  }) : _additional = additional;

  /// Build context used to resolve UI-specific data.
  final BuildContext context;
  final Map<String, dynamic> Function()? _additional;

  @override
  String get name => 'ui';

  /// Limits automatic collection; UI data is fetched only when the user
  /// explicitly triggers a manual report.
  @override
  bool get manualReportOnly => true;

  @override
  Map<String, dynamic> getData() {
    final media = MediaQuery.maybeOf(context);
    final theme = Theme.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final navigator = Navigator.maybeOf(context);
    final route = ModalRoute.of(context);

    return <String, dynamic>{
      'theme': {
        'brightness': theme.brightness.name,
        'primaryColor': theme.primaryColor.toARGBInt(),
        'colorScheme': {
          'brightness': theme.colorScheme.brightness.name,
          'primary': theme.colorScheme.primary.toARGBInt(),
          'secondary': theme.colorScheme.secondary.toARGBInt(),
          'background': theme.colorScheme.surface.toARGBInt(),
          'surface': theme.colorScheme.surface.toARGBInt(),
          'error': theme.colorScheme.error.toARGBInt(),
        },
        'textTheme': {
          'displayLarge': theme.textTheme.displayLarge?.fontSize,
          'displayMedium': theme.textTheme.displayMedium?.fontSize,
          'displaySmall': theme.textTheme.displaySmall?.fontSize,
          'headlineLarge': theme.textTheme.headlineLarge?.fontSize,
          'headlineMedium': theme.textTheme.headlineMedium?.fontSize,
          'headlineSmall': theme.textTheme.headlineSmall?.fontSize,
          'titleLarge': theme.textTheme.titleLarge?.fontSize,
          'titleMedium': theme.textTheme.titleMedium?.fontSize,
          'titleSmall': theme.textTheme.titleSmall?.fontSize,
          'bodyLarge': theme.textTheme.bodyLarge?.fontSize,
          'bodyMedium': theme.textTheme.bodyMedium?.fontSize,
          'bodySmall': theme.textTheme.bodySmall?.fontSize,
          'labelLarge': theme.textTheme.labelLarge?.fontSize,
          'labelMedium': theme.textTheme.labelMedium?.fontSize,
          'labelSmall': theme.textTheme.labelSmall?.fontSize,
        },
        'platform': theme.platform.name,
      },
      'mediaQuery': media == null
          ? null
          : {
              'size': {
                'width': media.size.width,
                'height': media.size.height,
              },
              'devicePixelRatio': media.devicePixelRatio,
              'padding': media.padding.toString(),
              'viewInsets': media.viewInsets.toString(),
              'viewPadding': media.viewPadding.toString(),
              'textScaleFactor': media.textScaler.toString(),
              'orientation': media.orientation.name,
              'platformBrightness': media.platformBrightness.name,
              'accessibleNavigation': media.accessibleNavigation,
              'boldText': media.boldText,
              'disableAnimations': media.disableAnimations,
              'highContrast': media.highContrast,
              'invertColors': media.invertColors,
              'alwaysUse24HourFormat': media.alwaysUse24HourFormat,
            },
      'locale': locale?.toLanguageTag(),
      'textDirection': Directionality.of(context).name,
      'navigation': navigator == null
          ? null
          : {
              'canPop': navigator.canPop(),
              'userGestureInProgress': navigator.userGestureInProgress,
              'routeName': route?.settings.name,
            },
      'scheduler': {
        'timeDilation': timeDilation,
        'frameTime': SchedulerBinding.instance.currentFrameTimeStamp.toString(),
      },
      if (_additional != null) ..._additional(),
    };
  }
}
