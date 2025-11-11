// Demonstrates how to initialize and consume the bug_handler package inside
// a small Flutter experience.
import 'dart:async';
import 'dart:math';

import 'package:bug_handler/bug_handler.dart';
import 'package:bug_handler/flutter/bindings.dart';
import 'package:bug_handler/flutter/error_boundary.dart';
import 'package:bug_handler/helpers.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = ClientConfig(
    environment: 'development',
    baseProviders: [
      AppContextProvider(),
      DeviceContextProvider(),
      NetworkContextProvider(),
    ],
    additionalProviders: [
      UserContextProvider(
        id: 'demo-user',
        email: 'observer@example.com',
        role: 'qa',
        traits: const {'featureFlag': 'new-dashboard'},
      ),
    ],
    sanitizers: [
      DefaultSanitizer(),
    ],
    reporters: const [
      ConsoleReporter(prettyJson: true),
      ShareReporter(subjectPrefix: 'Bug Handler Demo'),
    ],
    policy: const Policy(
      minSeverity: Severity.warning,
      reportHandled: true,
      sampling: 1.0,
    ),
    maxBreadcrumbs: 200,
  );

  await BugReportBindings.runAppWithReporting(
    app: () => DemoApp(api: DemoApiClient()),
    config: config,
  );
}

class DemoApp extends StatelessWidget {
  const DemoApp({required this.api, super.key});

  final DemoApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bug_handler demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: DemoHomePage(api: api),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({required this.api, super.key});

  final DemoApiClient api;

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  int _counter = 0;
  bool _loading = false;
  String _statusMessage = 'Tap any action to interact with the demo.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('bug_handler demo'),
        actions: [
          IconButton(
            tooltip: 'Flush queued reports',
            onPressed: _flushPendingReports,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sendManualReport,
        icon: const Icon(Icons.report),
        label: const Text('Manual report'),
      ),
      body: ErrorBoundary(
        onException: (error) {
          setState(() {
            _statusMessage = 'Boundary captured: ${error.userMessage}';
          });
        },
        showDetails: true,
        child: Builder(
          builder: (context) {
            final boundary = ErrorBoundary.of(context);
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _StatusCard(
                  counter: _counter,
                  loading: _loading,
                  message: _statusMessage,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Increment counter'),
                      onPressed: _loading ? null : _incrementCounter,
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Load profile (guarded)'),
                      onPressed: _loading
                          ? null
                          : () {
                              unawaited(
                                boundary.guardFuture<void>(
                                  _loadProfile,
                                  source: 'demo.fetchProfile',
                                ),
                              );
                            },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.error_outline),
                      label: const Text('Throw sync error'),
                      onPressed: boundary.guardCallback(
                        _throwSyncError,
                        source: 'demo.syncCrash',
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.timeline),
                      label: const Text('Add breadcrumb'),
                      onPressed: _recordBreadcrumb,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Clear breadcrumbs'),
                      onPressed: () {
                        BugReportClient.instance.clearBreadcrumbs();
                        setState(() {
                          _statusMessage = 'Breadcrumb ring buffer cleared.';
                        });
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
      _statusMessage = 'Counter incremented to $_counter.';
    });
    BugReportClient.instance.addBreadcrumb(
      'Counter incremented',
      data: {'value': _counter},
    );
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _statusMessage = 'Requesting profile…';
    });

    try {
      final profile = await widget.api.fetchProfile();
      setState(() {
        _statusMessage = 'Loaded profile for $profile';
      });
      BugReportClient.instance.addBreadcrumb(
        'Profile load succeeded',
        data: {'profile': profile},
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _throwSyncError() {
    throw UnexpectedException(
      devMessage: 'Crash button pressed',
      userMessage: 'We crashed on purpose to demonstrate the boundary.',
      metadata: {
        'counter': _counter,
      },
    );
  }

  void _recordBreadcrumb() {
    BugReportClient.instance.addBreadcrumb(
      'User tapped breadcrumb button',
      data: {'counter': _counter},
    );
    setState(() {
      _statusMessage = 'Breadcrumb recorded. Total taps: $_counter';
    });
  }

  Future<void> _sendManualReport() async {
    final exception = UnexpectedException(
      devMessage: 'Manual diagnostics requested from FAB.',
      userMessage: 'Manual report sent from the sample app.',
      metadata: {
        'counter': _counter,
        'statusMessage': _statusMessage,
      },
    );

    await BugReportClient.instance.capture(
      exception,
      manual: true,
      additionalContext: {
        'screen': 'DemoHomePage',
        'notes': 'Triggered by user action',
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Manual report dispatched'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _flushPendingReports() async {
    setState(() {
      _statusMessage = 'Flushing outbox…';
    });
    await BugReportClient.instance.flush();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Outbox flushed (see console).')),
    );
    setState(() {
      _statusMessage = 'Outbox flush requested.';
    });
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.counter,
    required this.loading,
    required this.message,
  });

  final int counter;
  final bool loading;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loading ? 'Loading…' : 'Ready',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            Text('Counter: $counter'),
          ],
        ),
      ),
    );
  }
}

class DemoApiClient {
  final Random _rng = Random();
  static const _names = [
    'Amina Chen',
    'Jasper Ortega',
    'Lina Navarro',
    'Noor Okoye',
  ];

  Future<String> fetchProfile() async {
    await Future.delayed(const Duration(milliseconds: 600));
    final success = _rng.nextDouble() > 0.4;
    if (success) {
      return _names[_rng.nextInt(_names.length)];
    }
    throw ApiException(
      httpStatusInfo: HttpStatusCodeInfo(503),
      endpoint: '/profile',
      method: 'GET',
      responseBody: {'message': 'Service temporarily unavailable'},
    );
  }
}
