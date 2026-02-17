import 'package:bug_handler/config/report_config.dart';
import 'package:bug_handler/config/severity.dart';
import 'package:bug_handler/context/built_in/app_context.dart';
import 'package:bug_handler/context/built_in/device_context.dart';
import 'package:bug_handler/core/bug_reporter.dart';
import 'package:bug_handler/core/error_handler.dart';
import 'package:bug_handler/exceptions/base_exception.dart';
import 'package:flutter/material.dart';

// 1. Define environments
enum AppEnvironment { dev, staging, prod }

// 2. Custom exception
class CounterException extends BaseException {
  CounterException({
    required super.userMessage,
    required super.devMessage,
    required this.currentValue,
    super.cause,
    super.stack,
    super.severity = ErrorSeverity.warning,
  }) : super(
          metadata: {
            'currentValue': currentValue,
          },
        );

  final int currentValue;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  void start() => runApp(const MyApp());
  // Initialize bug reporting
  await BugReporter.initialize(
    start,
    config: ReportConfig(
      sentryDsn:
          'https://86eec1c9cfa96a8eb858fe8889145f31@o4508369355997184.ingest.de.sentry.io/4508369363599440',
      // Replace with your DSN
      environments: AppEnvironment.values,
      currentEnvironment: AppEnvironment.dev,
      baseProviders: [
        AppContextProvider(),
        DeviceContextProvider(),
      ],
      minSeverity: ErrorSeverity.warning,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bug Reporter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Bug Reporter Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  Future<void> _incrementCounter() async {
    await ErrorHandler.wrap(
      () async {
        // Simulate an error when counter reaches 5
        if (_counter == 5) {
          throw CounterException(
            userMessage: 'Counter cannot exceed 5!',
            devMessage: 'Counter increment blocked at value 5',
            currentValue: _counter,
          );
        }

        setState(() {
          _counter++;
        });
      },
      source: 'MyHomePage._incrementCounter',
    );
  }

  Future<void> _triggerError() async {
    throw 'PROPABLY ERROR FROM MAC!';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _triggerError,
              child: const Text('Trigger Error'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
