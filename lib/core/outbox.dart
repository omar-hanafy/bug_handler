import 'dart:convert';
import 'dart:io';

import 'package:bug_handler/core/event.dart';
import 'package:bug_handler/reporters/reporter.dart';
import 'package:path_provider/path_provider.dart';

/// A simple, durable outbox backed by the filesystem.
/// - Each event is stored as a sanitized JSON file named `<id>.json`
/// - `pending()` lists and parses events in chronological order
/// - `ack(id)` deletes the corresponding file upon successful delivery
class Outbox {
  static const String _dirName = 'bug_report_outbox';

  Future<Directory> _ensureDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Enqueue a sanitized event for later delivery.
  Future<void> enqueue(ReportEvent event) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/${event.id}.json');
    final data = utf8.encode(event.toJson());
    await file.writeAsBytes(data, flush: true);
  }

  /// Returns all pending events in chronological order (by filename/ID).
  Future<List<ReportEvent>> pending() async {
    final dir = await _ensureDir();
    final entries = await dir.list().toList();
    final files = entries
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final result = <ReportEvent>[];
    for (final f in files) {
      try {
        final content = await f.readAsString();
        result.add(ReportEvent.fromJson(content));
      } catch (_) {
        // Corrupt file; delete to avoid blocking the queue.
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    return result;
  }

  /// Acknowledges successful delivery by deleting the stored file.
  Future<void> ack(String id) async {
    final dir = await _ensureDir();
    final file = File('${dir.path}/$id.json');
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Flushes pending events using the given reporter pipeline.
  Future<void> flushWith(Reporter pipeline) async {
    final items = await pending();
    for (final e in items) {
      final ok = await pipeline.send(e);
      if (ok) {
        await ack(e.id);
      }
    }
  }
}
