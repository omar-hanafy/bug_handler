import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../provider.dart';

/// Provides comprehensive UI-related context information for error reports
class UIContextProvider extends ContextProvider with CachedContextProvider {
  UIContextProvider(
    this.context, {
    super.additionalData,
  });

  final BuildContext context;

  @override
  String get name => 'ui_context';

  @override
  Map<String, dynamic> collectData() {
    final mediaQuery = MediaQuery.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final navigator = Navigator.of(context);

    return {
      'mediaQuery': mediaQuery.report,
      'theme': {
        'brightness': theme.brightness.name,
        'primaryColor': theme.primaryColor.toString(),
        'colorScheme': {
          'primary': theme.colorScheme.primary.toString(),
          'secondary': theme.colorScheme.secondary.toString(),
          'brightness': theme.colorScheme.brightness.name,
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
      },
      'locale': locale.toString(),
      'platform': Theme.of(context).platform.name,
      'textDirection': Directionality.of(context).name,
      'navigation': {
        'canPop': navigator.canPop(),
        'userGestureInProgress': navigator.userGestureInProgress,
        'widget': navigator.widget.toStringShort(),
        'route': ModalRoute.of(context)?.settings.name,
      },
      'scheduler': {
        'timeDilation': timeDilation,
        'vsyncTargetTime': SchedulerBinding.instance.currentFrameTimeStamp,
      },
      'additionalData': additionalData?.call(),
      // Add more UI-related data as needed
    };
  }
}

extension MediaQueryInfoEx on MediaQueryData {
  Map<String, dynamic> get report => {
    'deviceOrientation': '$orientation',
    'navigationMode': '$navigationMode',
    'padding': '$padding',
    'platformBrightness': '$platformBrightness',
    'viewInsets': '$viewInsets',
    'viewPadding': '$viewPadding',
    'size': {
      'width': size.width,
      'height': size.height,
    },
    'textScaler': '$textScaler',
    'accessibleNavigation': '$accessibleNavigation',
    'boldText': '$boldText',
    'disableAnimations': '$disableAnimations',
    'displayFeatures': '$displayFeatures',
    'gestureSettings': '$gestureSettings',
    'highContrast': '$highContrast',
    'invertColors': '$invertColors',
    'systemGestureInsets': '$systemGestureInsets',
    'alwaysUse24HourFormat': '$alwaysUse24HourFormat',
    'onOffSwitchLabels': '$onOffSwitchLabels',
  };
}
