import 'package:bug_handler/bug_handler.dart';
import 'package:flutter_test/flutter_test.dart';

/// A reporter that always blows up, simulating a broken delivery channel.
class _ThrowingReporter extends Reporter {
  const _ThrowingReporter();

  @override
  Future<bool> send(ReportEvent event) async =>
      throw StateError('delivery exploded');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final boom = UnexpectedException(devMessage: 'boom');

  // NOTE: BugReportClient is a singleton without reset, so the uninitialized
  // tests must run before the initialized group.
  group('before initialize', () {
    test('guard returns Err without throwing', () async {
      final res = await guard<int>(() async => throw Exception('fail'));
      expect(res.isErr, isTrue);
    });

    test('guardSync returns Err without throwing', () async {
      final res = guardSync<int>(() => throw Exception('fail'));
      expect(res.isErr, isTrue);
      // Let the fire-and-forget reporting microtask run; it must not throw.
      await Future<void>.delayed(Duration.zero);
    });

    test('captureSafely is a no-op', () async {
      await expectLater(
        BugReportClient.instance.captureSafely(boom),
        completes,
      );
    });

    test('capture (the throwing API) surfaces the StateError', () {
      expect(
        () => BugReportClient.instance.capture(boom),
        throwsStateError,
      );
    });
  });

  group('after initialize, with broken delivery and no outbox plugin', () {
    setUpAll(() async {
      // No path_provider in tests: outbox persistence throws, exercising the
      // post-delivery failure path inside captureSafely.
      await BugReportClient.instance.initialize(
        const ClientConfig(
          environment: 'test',
          reporters: [_ThrowingReporter()],
        ),
      );
    });

    test('captureSafely swallows delivery and outbox failures', () async {
      await expectLater(
        BugReportClient.instance.captureSafely(boom),
        completes,
      );
    });

    test('guard still returns Err when reporting fails', () async {
      final res = await guard<int>(() async => throw Exception('fail'));
      expect(res.isErr, isTrue);
    });

    test('guardSync still returns Err when reporting fails', () async {
      final res = guardSync<int>(() => throw Exception('fail'));
      expect(res.isErr, isTrue);
      await Future<void>.delayed(Duration.zero);
    });
  });
}
