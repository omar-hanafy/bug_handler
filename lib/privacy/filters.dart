// Filtering utilities for shaping the diagnostic payload before it leaves
// the device. These filters operate on *arbitrary nested* JSON-like maps and
// support dotted key paths with wildcards.
//
// Supported path syntax:
// - `a.b.c`         : exact path
// - `a.*.c`         : match any single key at `*`
// - `a.**.c`        : match any depth between `a` and `c`
// - `**.token`      : match any key named `token` at any depth
//
// Notes:
// - All operations are *non-mutating*: inputs are not modified in place.
// - Values are deep-copied structurally where necessary to avoid aliasing.
//
// Example:
// ```dart
// final filter = AllowListFilter({
//   'exception',             // keep entire exception object
//   'context.app',           // keep app context section
//   'context.device.model',  // keep only model from device context
//   'breadcrumbs',           // keep breadcrumbs list
// });
//
// final slim = filter.apply(eventMap);
// ```

/// Base interface for map filters.
mixin DataFilter {
  /// Returns a new filtered map. The input map is never mutated.
  Map<String, Object?> apply(Map<String, Object?> input);
}

/// Compose multiple filters in order (left to right).
class FilterChain implements DataFilter {
  /// Creates a filter chain that runs [filters] sequentially.
  FilterChain(this.filters);

  /// Filters that will process the data in sequence.
  final List<DataFilter> filters;

  @override
  Map<String, Object?> apply(Map<String, Object?> input) {
    var out = Map<String, Object?>.unmodifiable(input);
    for (final f in filters) {
      out = Map<String, Object?>.unmodifiable(f.apply(out));
    }
    return out;
  }
}

/// Keeps only the paths listed in [allowedPaths]. Everything else is dropped.
///
/// Paths may use `*` (single segment) and `**` (multi-segment) wildcards.
class AllowListFilter implements DataFilter {
  /// Creates an allow list filter retaining only the given [allowedPaths].
  AllowListFilter(
    Set<String> allowedPaths, {
    this.keepEmptyParents = false,
  }) : _paths = allowedPaths.map(_KeyPath.parse).toSet();

  /// If true, parents are kept even if all children are filtered out.
  final bool keepEmptyParents;

  final Set<_KeyPath> _paths;

  @override
  Map<String, Object?> apply(Map<String, Object?> input) {
    final result = <String, Object?>{};
    for (final kp in _paths) {
      _merge(result, _extractByPath(input, kp.segments));
    }
    if (!keepEmptyParents) _pruneEmpty(result);
    return result;
  }
}

/// Removes any keys that match the provided [deniedPaths].
///
/// Paths may use `*` (single segment) and `**` (multi-segment) wildcards.
class DenyListFilter implements DataFilter {
  /// Creates a deny list filter that removes values matching [deniedPaths].
  DenyListFilter(Set<String> deniedPaths)
      : _paths = deniedPaths.map(_KeyPath.parse).toSet();

  final Set<_KeyPath> _paths;

  @override
  Map<String, Object?> apply(Map<String, Object?> input) {
    final working = _cloneDeep(input)! as Map<String, Object?>;
    for (final kp in _paths) {
      _removeByPath(working, kp.segments);
    }
    _pruneEmpty(working);
    return working;
  }
}

// ---------- Implementation details below ----------

/// Represents a dotted path with `*` and `**` wildcards.
final class _KeyPath {
  _KeyPath(this.segments);

  factory _KeyPath.parse(String path) {
    final segments = path.split('.').where((s) => s.isNotEmpty).toList();
    return _KeyPath(segments);
  }

  final List<String> segments;
}

/// Recursively extract a subtree that matches [segments] from [source].
Map<String, Object?> _extractByPath(
  Map<String, Object?> source,
  List<String> segments,
) {
  if (segments.isEmpty) return _cloneMap(source);

  final head = segments.first;
  final tail = segments.sublist(1);

  // Double star: match any depth (including zero).
  if (head == '**') {
    // Option 1: consume zero segments – try matching the tail here.
    final here = _extractByPath(source, tail);

    // Option 2: consume one segment and continue with '**'.
    final deeper = <String, Object?>{};
    source.forEach((k, v) {
      if (v is Map<String, Object?>) {
        final sub = _extractByPath(v, segments); // still '**'
        if (sub.isNotEmpty) deeper[k] = sub;
      } else if (v is List) {
        final list = _extractFromList(v, segments);
        if (list.isNotEmpty) deeper[k] = list;
      }
    });

    return _merge({}, here)..addAll(deeper);
  }

  // Single star: match any single segment at this depth.
  if (head == '*') {
    final out = <String, Object?>{};
    source.forEach((k, v) {
      if (v is Map<String, Object?>) {
        final sub = _extractByPath(v, tail);
        if (sub.isNotEmpty) out[k] = sub;
      } else if (v is List) {
        final list = _extractFromList(v, tail);
        if (list.isNotEmpty) out[k] = list;
      } else if (tail.isEmpty) {
        // leaf wildcard
        out[k] = v;
      }
    });
    return out;
  }

  // Exact match on this segment.
  if (!source.containsKey(head)) return {};
  final value = source[head];

  if (value is Map<String, Object?>) {
    if (tail.isEmpty) return {head: _cloneMap(value)};
    final sub = _extractByPath(value, tail);
    return sub.isEmpty ? {} : {head: sub};
  } else if (value is List) {
    if (tail.isEmpty) return {head: _cloneList(value)};
    final list = _extractFromList(value, tail);
    return list.isNotEmpty ? {head: list} : {};
  } else {
    // Leaf value.
    return tail.isEmpty ? {head: value} : {};
  }
}

List<Object?> _extractFromList(List<Object?> src, List<String> segments) {
  final out = <Object?>[];
  for (final item in src) {
    if (item is Map<String, Object?>) {
      final sub = _extractByPath(item, segments);
      if (sub.isNotEmpty) out.add(sub);
    } else if (item is List) {
      final sub = _extractFromList(item, segments);
      if (sub.isNotEmpty) out.add(sub);
    } else if (segments.isEmpty) {
      out.add(item);
    }
  }
  return out;
}

void _removeByPath(Map<String, Object?> source, List<String> segments) {
  if (segments.isEmpty) return;

  final head = segments.first;
  final tail = segments.sublist(1);

  if (head == '**') {
    // Remove matches at this level
    _removeByPath(source, tail);
    // And deeper levels
    source.forEach((k, v) {
      if (v is Map<String, Object?>) {
        _removeByPath(v, segments); // still '**'
      } else if (v is List) {
        _removeFromList(v, segments);
      }
    });
    return;
  }

  if (head == '*') {
    final keys = List<String>.from(source.keys);
    for (final k in keys) {
      final v = source[k];
      if (v is Map<String, Object?>) {
        if (tail.isEmpty) {
          source.remove(k);
        } else {
          _removeByPath(v, tail);
        }
      } else if (v is List) {
        if (tail.isEmpty) {
          source.remove(k);
        } else {
          _removeFromList(v, tail);
        }
      } else if (tail.isEmpty) {
        source.remove(k);
      }
    }
    return;
  }

  if (!source.containsKey(head)) return;
  final value = source[head];

  if (tail.isEmpty) {
    source.remove(head);
    return;
  }

  if (value is Map<String, Object?>) {
    _removeByPath(value, tail);
  } else if (value is List) {
    _removeFromList(value, tail);
  }
}

void _removeFromList(List<Object?> src, List<String> segments) {
  for (var i = 0; i < src.length; i++) {
    final item = src[i];
    if (item is Map<String, Object?>) {
      _removeByPath(item, segments);
    } else if (item is List) {
      _removeFromList(item, segments);
    } else if (segments.isEmpty) {
      // remove leaf
      src.removeAt(i);
      i--;
    }
  }
}

void _pruneEmpty(Map<String, Object?> m) {
  final keys = List<String>.from(m.keys);
  for (final k in keys) {
    final v = m[k];
    if (v is Map<String, Object?>) {
      _pruneEmpty(v);
      if (v.isEmpty) m.remove(k);
    } else if (v is List) {
      _pruneEmptyList(v);
      if (v.isEmpty) m.remove(k);
    }
  }
}

void _pruneEmptyList(List<Object?> l) {
  for (var i = 0; i < l.length; i++) {
    final v = l[i];
    if (v is Map<String, Object?>) {
      _pruneEmpty(v);
      if (v.isEmpty) {
        l.removeAt(i);
        i--;
      }
    } else if (v is List) {
      _pruneEmptyList(v);
      if (v.isEmpty) {
        l.removeAt(i);
        i--;
      }
    }
  }
}

/// Merge [src] into [dst] deeply without overwriting existing branches.
Map<String, Object?> _merge(
    Map<String, Object?> dst, Map<String, Object?> src) {
  src.forEach((k, v) {
    if (v is Map<String, Object?>) {
      final existing = dst[k];
      if (existing is Map<String, Object?>) {
        dst[k] = _merge(existing, v);
      } else {
        dst[k] = _cloneMap(v);
      }
    } else if (v is List) {
      dst[k] = _cloneList(v);
    } else {
      dst[k] = v;
    }
  });
  return dst;
}

Object? _cloneDeep(Object? value) {
  if (value is Map<String, Object?>) return _cloneMap(value);
  if (value is List) return _cloneList(value);
  return value;
}

Map<String, Object?> _cloneMap(Map<String, Object?> m) {
  final out = <String, Object?>{};
  m.forEach((k, v) {
    out[k] = _cloneDeep(v);
  });
  return out;
}

List<Object?> _cloneList(List<Object?> l) {
  return l.map(_cloneDeep).toList(growable: true);
}
