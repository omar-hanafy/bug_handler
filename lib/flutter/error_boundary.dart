import 'dart:async';

import 'package:bug_reporting_system/core/client.dart';
import 'package:bug_reporting_system/core/guard.dart';
import 'package:bug_reporting_system/exceptions/base_exception.dart';
import 'package:bug_reporting_system/exceptions/unexpected_exception.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Signature for builders that render the fallback UI once an error is captured.
typedef ErrorFallbackBuilder = Widget Function(
  BuildContext context,
  BaseException error,
  VoidCallback onRetry,
  Future<void> Function() onReport,
);

/// A pragmatic error boundary for Flutter apps.
///
/// ### What it does well
/// - Provides a **local** place to render a fallback UI when an operation in
///   this subtree fails and is **reported** through the boundary (e.g. via
///   [guardFuture], [guardCallback], or [guardStream]).
/// - Integrates with your reporting pipeline via [BugReportClient].
/// - Lets you decide the UX via [fallbackBuilder] or use a sensible default.
///
/// ### What it doesn't try to do
/// - It **does not** intercept framework build/layout/paint exceptions. Those
///   should be wired globally via [BugReportBindings] (see `bindings.dart`).
///
/// ### Typical usage
/// ```dart
/// class ProfileScreen extends StatelessWidget {
///   const ProfileScreen({super.key});
///
///   @override
///   Widget build(BuildContext context) {
///     return ErrorBoundary(
///       onRetry: () => context.read<ProfileCubit>().refresh(),
///       child: _ProfileContent(),
///     );
///   }
/// }
///
/// class _ProfileContent extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     final boundary = ErrorBoundary.of(context);
///
///     return ElevatedButton(
///       onPressed: boundary.guardAsyncCallback(() async {
///         await context.read<ProfileCubit>().load();
///       }, source: 'ProfileScreen.load'),
///       child: const Text('Load profile'),
///     );
///   }
/// }
/// ```
class ErrorBoundary extends StatefulWidget {
  /// Wraps a subtree with error handling and reporting helpers.
  const ErrorBoundary({
    required this.child,
    this.fallbackBuilder,
    this.onException,
    this.onRetry,
    this.showDetails = false,
    super.key,
  });

  /// The subtree the boundary wraps.
  final Widget child;

  /// Optional custom fallback UI when an error is captured.
  final ErrorFallbackBuilder? fallbackBuilder;

  /// Called whenever a [BaseException] is captured by this boundary.
  final void Function(BaseException exception)? onException;

  /// Called when the user taps "Retry" in the default fallback UI.
  final VoidCallback? onRetry;

  /// Whether to show developer details (dev message, type) in the default UI.
  final bool showDetails;

  /// Obtain the nearest [ErrorBoundaryState] from the given [context].
  static ErrorBoundaryState of(BuildContext context) {
    final state = context.findAncestorStateOfType<ErrorBoundaryState>();
    assert(
      state != null,
      'ErrorBoundary.of(context) called with no ErrorBoundary ancestor.',
    );
    return state!;
  }

  @override
  State<ErrorBoundary> createState() => ErrorBoundaryState();
}

/// Backing state for [ErrorBoundary], exposing guard helpers to descendants.
class ErrorBoundaryState extends State<ErrorBoundary> {
  /// Default constructor; prefer using [ErrorBoundaryState.of] to obtain instances.
  ErrorBoundaryState();

  /// Obtain the nearest [ErrorBoundary] state to guard operations conveniently.
  factory ErrorBoundaryState.of(BuildContext context) {
    final state = context.findAncestorStateOfType<ErrorBoundaryState>();
    assert(
      state != null,
      'ErrorBoundaryState.of(context) called with no ErrorBoundaryState ancestor.',
    );
    return state!;
  }

  // === Public helpers ========================================================

  BaseException? _error;
  bool _reporting = false;

  /// Guard an async operation and route failures into this boundary.
  Future<T> guardFuture<T>(
    Future<T> Function() action, {
    String? source,
    FutureOr<void> Function(T value)? onSuccess,
    FutureOr<void> Function(BaseException e)? onError,
  }) async {
    final res = await guard<T>(
      action,
      source: source,
      onSuccess: onSuccess,
      onError: (e) async {
        await onError?.call(e);
        _setError(e);
      },
    );

    return res.match(
      ok: (v) => v,
      err: (e) => throw e, // propagate, while boundary shows fallback
    );
  }

  /// Wrap a synchronous callback (e.g., onTap) to capture thrown errors.
  VoidCallback guardCallback(
    VoidCallback action, {
    String? source,
    FutureOr<void> Function(BaseException e)? onError,
  }) {
    return () {
      try {
        action();
      } catch (e, s) {
        final normalized = _normalize(e, s, source: source);
        scheduleMicrotask(() async {
          await onError?.call(normalized);
          _setError(normalized);
          await _report(normalized);
        });
        // Re-throw so calling code can handle if it wants.
        // In typical UI callbacks, this is fine and will still show fallback.
        // ignore: only_throw_errors
        throw normalized;
      }
    };
  }

  /// Wrap an async callback to capture errors.
  AsyncCallback guardAsyncCallback(
    Future<void> Function() action, {
    String? source,
    FutureOr<void> Function(BaseException e)? onError,
  }) {
    return () async {
      await guardFuture<void>(
        () async => action(),
        source: source,
        onError: onError,
      );
    };
  }

  /// Transform a stream so errors are captured by this boundary.
  Stream<T> guardStream<T>(
    Stream<T> source, {
    String? sourceName,
    FutureOr<void> Function(BaseException e)? onError,
  }) {
    late StreamController<T> controller;
    controller = StreamController<T>(
      sync: true,
      onListen: () {
        final sub = source.listen(
          controller.add,
          onError: (Object error, StackTrace stack) async {
            final normalized = _normalize(error, stack, source: sourceName);
            await onError?.call(normalized);
            _setError(normalized);
            await _report(normalized);
            controller.addError(normalized, stack);
          },
          onDone: controller.close,
          cancelOnError: false,
        );
        controller.onCancel = sub.cancel;
      },
    );
    return controller.stream;
  }

  /// Programmatically show an error in this boundary (e.g., from state).
  void show(BaseException error) {
    _setError(error);
  }

  // === Internal helpers ======================================================

  void _setError(BaseException e) {
    if (!mounted) return;
    setState(() => _error = e);
    widget.onException?.call(e);
  }

  Future<void> _report(BaseException e) async {
    if (_reporting) return;
    _reporting = true;
    try {
      final event = await BugReportClient.instance.createEvent(e, manual: true);
      await BugReportClient.instance.report(event);
    } finally {
      _reporting = false;
    }
  }

  void _retry() {
    if (!mounted) return;
    setState(() => _error = null);
    widget.onRetry?.call();
  }

  Future<void> _reportCurrent() async {
    final error = _error;
    if (error == null) return;
    await _report(error);
  }

  BaseException _normalize(Object error, StackTrace stack, {String? source}) {
    if (error is BaseException) return error;
    // We assume an UnexpectedException type exists in the library.
    // It should accept (cause, stack, user/dev messages, severity, etc.).
    return UnexpectedException(
      cause: error,
      stack: stack,
      devMessage:
          source != null ? 'Unhandled error in $source' : 'Unhandled error',
    );
  }

  // === Build ================================================================

  @override
  Widget build(BuildContext context) {
    final err = _error;
    if (err == null) return widget.child;

    final builder = widget.fallbackBuilder ?? _defaultFallback;
    return builder(context, err, _retry, _reportCurrent);
  }

  Widget _defaultFallback(
    BuildContext context,
    BaseException error,
    VoidCallback onRetry,
    Future<void> Function() onReport,
  ) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    final onColor = theme.colorScheme.onError;

    return Material(
      color: color.withValues(alpha: 0.06),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: color.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 36, color: color),
                  const SizedBox(height: 12),
                  Text(
                    'Something went wrong',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.userMessage,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.showDetails) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        '${error.runtimeType}: ${error.devMessage}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: onColor,
                        ),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await onReport();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Error report submitted'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.report),
                        label: const Text('Report'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
