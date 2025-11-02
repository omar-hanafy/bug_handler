import 'package:bug_reporting_system/core/event.dart';
import 'package:bug_reporting_system/reporters/reporter.dart';

/// Fans out delivery to multiple reporters.
///
/// A send/share is considered successful if **any** reporter succeeds.
/// Failures from individual reporters are swallowed to keep the pipeline resilient.
class CompositeReporter extends Reporter {
  /// Creates a composite reporter that delegates to the provided [reporters].
  const CompositeReporter(this.reporters);

  /// Reporters will be called in order. Keep side-effecting reporters first if ordering matters.
  final List<Reporter> reporters;

  @override
  Future<bool> send(ReportEvent event) async {
    var anySuccess = false;

    for (final r in reporters) {
      try {
        final ok = await r.send(event);
        anySuccess = anySuccess || ok;
      } catch (_) {
        // Intentionally swallow to let other reporters run.
      }
    }

    return anySuccess;
  }

  @override
  Future<bool> share(ReportEvent event) async {
    var anySuccess = false;

    for (final r in reporters) {
      try {
        final ok = await r.share(event);
        anySuccess = anySuccess || ok;
      } catch (_) {
        // Intentionally swallow.
      }
    }

    return anySuccess;
  }
}
