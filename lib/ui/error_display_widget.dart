// ignore_for_file: omit_local_variable_types

import 'package:bug_handler/core/bug_reporter.dart';
import 'package:bug_handler/core/error_handler.dart';
import 'package:bug_handler/exceptions/flutter_error_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_helper_utils/flutter_helper_utils.dart';

/// Configuration for error display appearance and behavior
class ErrorDisplayConfig {
  const ErrorDisplayConfig({
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
    this.textColor,
    this.secondaryTextColor,
    this.buttonColor,
    this.showErrorDetails = false,
    this.allowRetry = true,
    this.allowShare = true,
    this.customIcon,
    this.customErrorMessage,
    this.customSubMessage,
    this.onRetry,
    this.onShare,
  });

  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final Color? textColor;
  final Color? secondaryTextColor;
  final Color? buttonColor;
  final bool showErrorDetails;
  final bool allowRetry;
  final bool allowShare;
  final IconData? customIcon;
  final String? customErrorMessage;
  final String? customSubMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onShare;

  ErrorDisplayConfig copyWith({
    Color? backgroundColor,
    Color? borderColor,
    Color? iconColor,
    Color? textColor,
    Color? secondaryTextColor,
    Color? buttonColor,
    bool? showErrorDetails,
    bool? allowRetry,
    bool? allowShare,
    IconData? customIcon,
    String? customErrorMessage,
    String? customSubMessage,
    VoidCallback? onRetry,
    VoidCallback? onShare,
  }) {
    return ErrorDisplayConfig(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      borderColor: borderColor ?? this.borderColor,
      iconColor: iconColor ?? this.iconColor,
      textColor: textColor ?? this.textColor,
      secondaryTextColor: secondaryTextColor ?? this.secondaryTextColor,
      buttonColor: buttonColor ?? this.buttonColor,
      showErrorDetails: showErrorDetails ?? this.showErrorDetails,
      allowRetry: allowRetry ?? this.allowRetry,
      allowShare: allowShare ?? this.allowShare,
      customIcon: customIcon ?? this.customIcon,
      customErrorMessage: customErrorMessage ?? this.customErrorMessage,
      customSubMessage: customSubMessage ?? this.customSubMessage,
      onRetry: onRetry ?? this.onRetry,
      onShare: onShare ?? this.onShare,
    );
  }
}

/// Widget to display when a Flutter error occurs
class ErrorDisplayWidget extends StatefulWidget {
  const ErrorDisplayWidget({
    required this.details,
    this.config = const ErrorDisplayConfig(),
    this.fullScreen = false,
    this.onErrorHandled,
    super.key,
  });

  final FlutterErrorDetails details;
  final ErrorDisplayConfig config;
  final bool fullScreen;
  final void Function(FlutterErrorException)? onErrorHandled;

  @override
  State<ErrorDisplayWidget> createState() => _ErrorDisplayWidgetState();
}

class _ErrorDisplayWidgetState extends State<ErrorDisplayWidget> {
  late FlutterErrorException _exception;
  bool _isRetrying = false;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _exception = FlutterErrorException(widget.details);
    _handleError();
  }

  Future<void> _handleError() async {
    try {
      await ErrorHandler.handle(
        _exception,
        _exception.stack ?? StackTrace.current,
        source: 'ErrorDisplayWidget',
      );
      widget.onErrorHandled?.call(_exception);
    } catch (e, s) {
      debugPrint('Error handling exception: $e\n$s');
    }
  }

  Future<void> _retryOperation() async {
    if (_isRetrying) return;

    setState(() => _isRetrying = true);
    try {
      widget.config.onRetry?.call();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, s) {
      debugPrint('Error retrying operation: $e\n$s');
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }

  Future<void> _shareError() async {
    if (_isSharing) return;

    setState(() => _isSharing = true);
    try {
      final report = await BugReporter.instance.createReport(
        _exception,
        manualReport: true,
      );
      await report.share();
    } catch (e, s) {
      debugPrint('Error sharing report: $e\n$s');
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = widget.config;

    Widget content = _buildErrorContent(
      large: widget.fullScreen,
      theme: theme,
    );

    if (widget.fullScreen) {
      content = Material(
        color: config.backgroundColor ?? theme.scaffoldBackgroundColor,
        child: SafeArea(child: content),
      );
    }

    return content;
  }

  Widget _buildErrorContent({
    required bool large,
    required ThemeData theme,
  }) {
    final config = widget.config;
    final canPop = Navigator.canPop(context);

    return Container(
      width: large ? double.infinity : 200,
      padding: EdgeInsets.all(large ? 24 : 16),
      margin: large ? null : const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            config.backgroundColor ?? theme.colorScheme.error.addOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: config.borderColor ?? theme.colorScheme.error.addOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            config.customIcon ?? Icons.error_outline,
            color: config.iconColor ?? theme.colorScheme.error,
            size: large ? 48 : 24,
          ),
          SizedBox(height: large ? 16 : 8),
          Text(
            config.customErrorMessage ??
                (large ? 'Oops! Something went wrong' : 'An error occurred'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: config.textColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (large) ...[
            const SizedBox(height: 8),
            Text(
              config.customSubMessage ??
                  'Our team has been notified and is working on a fix.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    config.secondaryTextColor ??
                    theme.colorScheme.onSurface.addOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (config.showErrorDetails) ...[
              const SizedBox(height: 16),
              _ErrorDetails(exception: _exception),
            ],
          ],
          const SizedBox(height: 16),
          _buildActionButtons(canPop, theme),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool canPop, ThemeData theme) {
    final config = widget.config;
    final buttonColor = config.buttonColor ?? theme.colorScheme.error;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (canPop)
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Go Back'),
            style: TextButton.styleFrom(foregroundColor: buttonColor),
          ),
        if (config.allowRetry && config.onRetry != null)
          TextButton.icon(
            onPressed: _isRetrying ? null : _retryOperation,
            icon: _isRetrying
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: buttonColor,
                    ),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(_isRetrying ? 'Retrying...' : 'Retry'),
            style: TextButton.styleFrom(foregroundColor: buttonColor),
          ),
        if (config.allowShare)
          TextButton.icon(
            onPressed: _isSharing ? null : _shareError,
            icon: _isSharing
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: buttonColor,
                    ),
                  )
                : const Icon(Icons.share, size: 16),
            label: Text(_isSharing ? 'Sharing...' : 'Share Error Report'),
            style: TextButton.styleFrom(foregroundColor: buttonColor),
          ),
      ],
    );
  }
}

class _ErrorDetails extends StatelessWidget {
  const _ErrorDetails({
    required this.exception,
  });

  final FlutterErrorException exception;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Error Details:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            exception.devMessage,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
