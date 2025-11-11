// Sanitization pipeline for privacy and size control.
//
// Sanitizers operate on JSON-like `Map<String, dynamic>` payloads and are
// typically invoked by the client configuration before delivery:
//
// ```dart
// var data = event.toMap();
// for (final s in config.sanitizers) {
//   data = s.sanitize(data);
// }
// final sanitizedEvent = event.copyWithRawMap(data);
// ```
//
// This file provides:
// - [Sanitizer] interface
// - [SanitizerChain] composition
// - [DefaultSanitizer] (key-based + content-based masking)
// - [RegexValueSanitizer] (pattern rewrites)
// - [MaxDepthSanitizer] (prune deep structures)
// - [TruncatingSanitizer] (cap string/list/map lengths)
// - [SizeBudgetSanitizer] (approximate JSON size budget)
// - [FilterSanitizer] (bridges filters with sanitizers)
import 'dart:convert';

import 'package:bug_handler/core/event.dart';
import 'package:bug_handler/privacy/filters.dart';

/// Base interface for sanitizers.
mixin Sanitizer {
  /// Returns a new sanitized map. The input is never mutated.
  Map<String, dynamic> sanitize(Map<String, dynamic> data);
}

/// Compose sanitizers in order.
class SanitizerChain implements Sanitizer {
  /// Creates a sanitizer chain that applies [sanitizers] sequentially.
  SanitizerChain(this.sanitizers);

  /// Sanitizers executed in sequence.
  final List<Sanitizer> sanitizers;

  @override
  Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    var out = Map<String, dynamic>.unmodifiable(data);
    for (final s in sanitizers) {
      out = Map<String, dynamic>.unmodifiable(s.sanitize(out));
    }
    return out;
  }
}

/// Bridge to apply a [DataFilter] as a [Sanitizer].
class FilterSanitizer implements Sanitizer {
  /// Wraps a [DataFilter] so it can be used as a sanitizer in pipelines.
  FilterSanitizer(this.filter);

  /// Underlying filter invoked during sanitization.
  final DataFilter filter;

  @override
  Map<String, dynamic> sanitize(Map<String, dynamic> data) =>
      filter.apply(data);
}

/// Default, privacy-first sanitizer that masks known sensitive fields by key
/// (e.g., "password", "token", "authorization", etc.) and optionally applies
/// content-based masking for values that *look* like secrets (JWTs, access
/// keys, long base64 tokens, card numbers).
class DefaultSanitizer implements Sanitizer {
  /// Creates a default sanitizer with optional overrides for matching and masking.
  DefaultSanitizer({
    SensitiveFieldMatcher? matcher,
    MaskingStrategy? fieldMask,
    MaskingStrategy? contentMask,
    this.enableContentBasedDetection = true,
  })  : _matcher = matcher ?? SensitiveFieldMatcher(),
        _fieldMask = fieldMask ?? const MaskingStrategy(),
        _contentMask =
            contentMask ?? const MaskingStrategy(keepStart: 2, keepEnd: 2);

  final SensitiveFieldMatcher _matcher;
  final MaskingStrategy _fieldMask;
  final MaskingStrategy _contentMask;

  /// If true, values that *look* like secrets are masked even if their keys
  /// are not sensitive (e.g., raw tokens in arrays).
  final bool enableContentBasedDetection;

  @override
  Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    return _sanitizeAny(data, const [], isTopLevel: true)
        as Map<String, dynamic>;
  }

  Object _sanitizeAny(Object? value, List<String> path,
      {bool isTopLevel = false}) {
    if (value is Map<String, dynamic>) {
      return _sanitizeMap(value, path);
    }
    if (value is List) {
      return _sanitizeList(value, path);
    }
    if (value is String) {
      // If any path segment is sensitive, mask aggressively.
      if (_matcher.matchesAny(path)) return _fieldMask.mask(value);
      if (enableContentBasedDetection) {
        final detected = _detectSecretLike(value);
        if (detected) return _contentMask.mask(value);
      }
      // Special handling: credit-card-like digits
      if (_looksLikeCardNumber(value)) return _contentMask.maskCard(value);
      return value;
    }
    return value ?? '';
  }

  Map<String, dynamic> _sanitizeMap(
      Map<String, dynamic> input, List<String> path) {
    final out = <String, dynamic>{};
    input.forEach((k, v) {
      final p = [...path, k.toLowerCase()];
      if (_matcher.matches(k)) {
        out[k] = _fieldMask.mask(_stringify(v));
      } else {
        out[k] = _sanitizeAny(v, p);
      }
    });
    return out;
  }

  List<dynamic> _sanitizeList(List<dynamic> input, List<String> path) {
    return input.map((v) => _sanitizeAny(v, path)).toList(growable: true);
  }

  bool _detectSecretLike(String s) {
    // JWT: header.payload.signature (two dots) with base64url segments.
    if (_jwtRegex.hasMatch(s)) return true;
    // AWS Access Key ID (AKIA... or ASIA...) style
    if (_awsAccessKeyId.hasMatch(s)) return true;
    // Long base64/base62 tokens
    if (_longToken.hasMatch(s)) return true;
    // Bearer tokens in headers
    if (_bearerRegex.hasMatch(s)) return true;
    return false;
  }

  bool _looksLikeCardNumber(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 13 && digits.length <= 19;
  }
}

/// Rewrites any string values that match a given regex to a replacement.
/// Useful for emails/phones if you want to aggressively strip PII.
class RegexValueSanitizer implements Sanitizer {
  /// Creates a regex-based sanitizer with replacement [rules].
  RegexValueSanitizer(this.rules);

  /// Map of pattern → replacement (applied to all strings recursively).
  final Map<RegExp, String> rules;

  @override
  Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    Object walk(Object? v) {
      if (v is Map<String, dynamic>) {
        return v.map((k, val) => MapEntry(k, walk(val)));
      } else if (v is List) {
        return v.map(walk).toList();
      } else if (v is String) {
        var s = v;
        for (final entry in rules.entries) {
          s = s.replaceAll(entry.key, entry.value);
        }
        return s;
      }
      return v ?? '';
    }

    return walk(data) as Map<String, dynamic>;
  }
}

/// Prunes nested structures beyond [maxDepth]. Replaces pruned nodes with
/// a marker to signal redaction.
class MaxDepthSanitizer implements Sanitizer {
  /// Creates a depth limiter that replaces deep structures beyond [maxDepth].
  const MaxDepthSanitizer(
      {this.maxDepth = 8, this.redactionMarker = '<redacted:depth>'});

  /// Maximum depth allowed before structures are redacted.
  final int maxDepth;

  /// Marker stored in place of pruned data.
  final String redactionMarker;

  @override
  Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    Object walk(Object? v, int depth) {
      if (depth >= maxDepth) return redactionMarker;
      if (v is Map<String, dynamic>) {
        return v.map((k, val) => MapEntry(k, walk(val, depth + 1)));
      } else if (v is List) {
        return v.map((it) => walk(it, depth + 1)).toList();
      }
      return v ?? '';
    }

    return walk(data, 0) as Map<String, dynamic>;
  }
}

/// Caps string length, list length, and map entry count to prevent
/// oversized payloads.
class TruncatingSanitizer implements Sanitizer {
  /// Creates a truncating sanitizer with caps for strings, lists, and maps.
  const TruncatingSanitizer({
    this.maxString = 1000,
    this.maxList = 200,
    this.maxMapEntries = 200,
    this.overflowMarker = '…',
  });

  /// Maximum characters permitted for string values.
  final int maxString;

  /// Maximum items permitted for list values.
  final int maxList;

  /// Maximum entries permitted for map values.
  final int maxMapEntries;

  /// Marker appended to indicate truncated content.
  final String overflowMarker;

  @override
  Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    Object walk(Object? v) {
      if (v is String) {
        if (v.length > maxString) {
          return v.substring(0, maxString) + overflowMarker;
        }
        return v;
      } else if (v is List) {
        if (v.length > maxList) {
          final head = v.take(maxList).map(walk).toList();
          return [
            ...head,
            '[$overflowMarker ${v.length - maxList} more items]'
          ];
        }
        return v.map(walk).toList();
      } else if (v is Map<String, dynamic>) {
        if (v.length > maxMapEntries) {
          final keys = v.keys.take(maxMapEntries).toList(growable: false);
          final trimmed = <String, dynamic>{};
          for (final k in keys) {
            trimmed[k] = walk(v[k]);
          }
          trimmed['__truncated__'] =
              '${v.length - maxMapEntries} more entries $overflowMarker';
          return trimmed;
        }
        return v.map((k, val) => MapEntry(k, walk(val)));
      }
      return v ?? '';
    }

    return walk(data) as Map<String, dynamic>;
  }
}

/// Ensures the serialized JSON stays under [maxBytes]. If the payload exceeds
/// the budget, the sanitizer drops entries heuristically (starting with the
/// largest string/list/map values) until the size fits. You may pin keys that
/// must be retained via [pinnedTopLevelKeys].
class SizeBudgetSanitizer implements Sanitizer {
  /// Creates a size budget sanitizer that trims payloads to [maxBytes].
  SizeBudgetSanitizer({
    required this.maxBytes,
    this.pinnedTopLevelKeys = const {'exception', 'timestamp', 'fingerprints'},
    this.overflowMarker = '<redacted:size>',
  }) : assert(maxBytes > 0, 'maxBytes must be greater than zero');

  /// Maximum payload size in bytes.
  final int maxBytes;

  /// Keys that should be retained even when trimming for size.
  final Set<String> pinnedTopLevelKeys;

  /// Marker stored when entries are dropped due to size constraints.
  final String overflowMarker;

  @override
  Map<String, dynamic> sanitize(Map<String, dynamic> data) {
    final out = Map<String, dynamic>.from(data);

    int sizeOf(Map<String, dynamic> m) => utf8.encode(jsonEncode(m)).length;

    if (sizeOf(out) <= maxBytes) return out;

    // Build a sortable list of top-level keys by their approximate size.
    final entries = <_SizedEntry>[];
    out.forEach((k, v) {
      entries.add(_SizedEntry(k, v, _approxSize(v)));
    });

    // Keep pinned keys at the end of the removal queue.
    entries.sort((a, b) {
      final ap = pinnedTopLevelKeys.contains(a.key) ? 1 : 0;
      final bp = pinnedTopLevelKeys.contains(b.key) ? 1 : 0;
      if (ap != bp) return ap - bp; // non-pinned first
      return b.size.compareTo(a.size); // larger first
    });

    // Drop/replace largest non-pinned items first.
    for (final e in entries) {
      if (pinnedTopLevelKeys.contains(e.key)) continue;
      out[e.key] = overflowMarker;
      if (sizeOf(out) <= maxBytes) return out;
    }

    // If still too large, truncate pinned items by stringifying.
    for (final e in entries.where((e) => pinnedTopLevelKeys.contains(e.key))) {
      out[e.key] = overflowMarker;
      if (sizeOf(out) <= maxBytes) return out;
    }

    return out;
  }

  static int _approxSize(Object? v) {
    if (v is String) return v.length;
    if (v is List) return v.length;
    if (v is Map) return v.length;
    return 8; // small constant for scalars
  }
}

final class _SizedEntry {
  _SizedEntry(this.key, this.value, this.size);

  final String key;
  final Object? value;
  final int size;
}

/// Convenience to apply a sanitizer directly to a [ReportEvent].
extension ReportEventSanitizer on Sanitizer {
  /// Returns a copy of [event] with the sanitized payload embedded.
  ReportEvent sanitizeEvent(ReportEvent event) {
    final m = event.toMap();
    final s = sanitize(m);
    return event.withPayload(s);
  }
}

/// Matches sensitive keys and/or path segments.
class SensitiveFieldMatcher {
  /// Creates a matcher with optional [extraKeys] to extend the defaults.
  SensitiveFieldMatcher({Set<String>? extraKeys})
      : keys = _defaultSensitiveKeys.union(extraKeys ?? const {});

  /// Case-insensitive key names that should be masked.
  final Set<String> keys;

  /// Returns true if the immediate key is sensitive.
  bool matches(String key) {
    final k = key.toLowerCase().trim();
    if (keys.contains(k)) return true;
    // also treat underscores/dashes variants as equal
    final normalized = k.replaceAll(RegExp(r'[-_\s]'), '');
    return keys.contains(normalized);
  }

  /// Returns true if any path segment is sensitive.
  bool matchesAny(Iterable<String> pathSegments) {
    for (final seg in pathSegments) {
      if (matches(seg)) return true;
    }
    return false;
  }
}

/// Strategy for masking strings while preserving limited structure.
class MaskingStrategy {
  /// Creates a masking strategy describing how many characters to keep visible.
  const MaskingStrategy({
    this.maskChar = '*',
    this.keepStart = 1,
    this.keepEnd = 1,
    this.minMasked = 2,
  })  : assert(keepStart >= 0, 'keepStart must be non-negative'),
        assert(keepEnd >= 0, 'keepEnd must be non-negative'),
        assert(minMasked >= 0, 'minMasked must be non-negative');

  /// Character used to mask hidden portions.
  final String maskChar;

  /// Number of characters preserved at the start.
  final int keepStart;

  /// Number of characters preserved at the end.
  final int keepEnd;

  /// Minimum number of masked characters enforced.
  final int minMasked;

  /// Masks the provided [input] using the strategy configuration.
  String mask(String input) {
    if (input.isEmpty) return '';
    final total = input.length;
    final visible = keepStart + keepEnd;
    final maskedCount = (total - visible).clamp(minMasked, total);
    if (maskedCount <= 0) return maskChar * total;
    final start = input.substring(0, keepStart.clamp(0, total));
    final end = input.substring(total - keepEnd.clamp(0, total));
    return '$start${maskChar * maskedCount}$end';
  }

  /// Special case for card-like sequences: mask all but last 4 digits and
  /// keep spacing where possible.
  String maskCard(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return mask(input);
    final last4 = digits.substring(digits.length - 4);
    return '${maskChar * (digits.length - 4)}$last4';
  }
}

// --- Heuristics for content-based detection ---

final RegExp _jwtRegex =
    RegExp(r'^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$');
final RegExp _awsAccessKeyId = RegExp(r'^(AKIA|ASIA)[0-9A-Z]{16}$');
final RegExp _longToken = RegExp(r'^[A-Za-z0-9\-_.]{24,}$');
final RegExp _bearerRegex = RegExp(r'^\s*Bearer\s+.+', caseSensitive: false);

String _stringify(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  try {
    return jsonEncode(v);
  } catch (_) {
    return v.toString();
  }
}

// A reasonably comprehensive default list of sensitive keys. Keep minimal
// overlap and prefer normalized forms. All comparisons are case-insensitive.
// You can augment this via `SensitiveFieldMatcher(extraKeys: {...})`.
const Set<String> _defaultSensitiveKeys = {
  // Auth
  'authorization',
  'auth',
  'bearer',
  'basic',
  'apikey',
  'api_key',
  'api-key',
  'token',
  'access_token',
  'refresh_token',
  'id_token',
  'session_token',
  'client_secret',
  'clientsecret',
  'secret',
  'private_key',
  'public_key',

  // Passwords & credentials
  'password',
  'passwd',
  'pwd',
  'passphrase',

  // Financial
  'card',
  'cardnumber',
  'card_number',
  'cvv',
  'cvc',
  'iban',
  'swift',
  'bic',

  // PII
  'email',
  'phone',
  'phone_number',
  'mobile',
  'ssn',
  'tax_id',
  'passport',
  'drivers_license',

  // Device/Location identifiers
  'device_id',
  'imei',
  'mac',
  'geolocation',
  'coordinates',

  // Generic flags
  'private',
  'sensitive',
  'confidential',
  'secretkey',
  'secure',
  'encrypted',
};
