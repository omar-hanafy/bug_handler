---
name: tune-privacy
description: >-
  Use when configuring or debugging bug_handler sanitizers and filters - masking
  PII/secrets in reports, DenyListFilter/AllowListFilter paths, payload size limits,
  fields arriving masked that should be readable, fields arriving readable that should be
  masked, or compliance requirements on diagnostic data.
---

# Tune the privacy pipeline (sanitizers and filters)

Sanitizers run in ClientConfig order over `event.toMap()`; the result is the ONLY
payload reporters and the outbox ever see. Getting order or paths wrong either
leaks PII or destroys the diagnostic value of reports.

## Canonical chain and why the order

```dart
sanitizers: [
  FilterSanitizer(DenyListFilter({...})),  // 1. structurally REMOVE what must never leave
  DefaultSanitizer(),                      // 2. mask secrets/PII by key + content
  const MaxDepthSanitizer(maxDepth: 8),    // 3. prune pathological nesting
  const TruncatingSanitizer(maxString: 2000, maxList: 100, maxMapEntries: 100),
  SizeBudgetSanitizer(maxBytes: 64 * 1024) // 5. LAST: hard size cap
]
```

- Deny/allow filters FIRST: removal beats masking for data that must not leave
  the device at all (masked values still reveal length/presence).
- `SizeBudgetSanitizer` LAST: it measures the final JSON. It drops the largest
  non-pinned TOP-LEVEL entries first (pinned by default: `exception`,
  `timestamp`, `fingerprints`) and will even redact pinned keys as a
  last resort - budget generously (production uses 48-64 KB).
- An `AllowListFilter`, when used, defines the ENTIRE payload shape: anything
  not matched is gone, including `exception` itself if you forget to allow it.
  Always include at least `{'exception', 'timestamp', 'fingerprints', 'handled', 'id'}`.

## Filter path syntax (top-level keys are the payload's, not "event.")

Payload top-level keys: `id`, `timestamp`, `handled`, `exception`, `context`,
`fingerprints`, `breadcrumbs`, `attachments`. Provider data sits under
`context.<providerName>` (`context.app`, `context.device`, `context.network`,
`context.user`, plus custom names).

- `a.b.c` exact; `a.*.c` exactly one segment; `a.**.c` any depth (including
  zero); `**.token` any key named token anywhere. Filters recurse into lists of
  maps. There is no negation and no regex in paths.

Proven deny-list for stable device identifiers (from production):
`context.app.buildSignature`, `context.device.fingerprint`,
`context.device.identifierForVendor`, `context.device.hostName`,
`context.device.userName`, `context.device.computerName`,
`context.device.systemGUID`, `context.device.utsname.nodename`. Add
`context.network.wifi` when SSID/BSSID must not leave the device.

## DefaultSanitizer behavior you must know before debugging

Masks by KEY (case-insensitive, underscore/dash/space-insensitive): auth/token/
secret family, passwords, card/cvv/iban, email, phone, ssn/passport, device_id/
imei/mac, geolocation/coordinates, and generic flags like `private`, `secure`,
`encrypted`. ANY path segment being sensitive masks everything below it.

Masks by CONTENT (`enableContentBasedDetection: true` default) - the three
false-positive generators:
1. Any string matching `[A-Za-z0-9-_.]{24,}` entirely -> masked as a token.
   Long IDs, slugs, file names without spaces get caught.
2. Any string whose DIGITS count to 13..19 -> masked like a card number
   (keeps last 4). Timestamps-with-offsets, long order numbers get caught.
3. JWT-shaped (`x.y.z` base64url) and `Bearer ...` strings -> masked.

"Why is this field masked?!" is almost always rule 1 or 2, or a sensitive
ancestor key (e.g. everything under a key named `auth`). Fixes, in preference
order: rename the key to something non-sensitive AND non-matching; restructure
so the value is not a bare 24+ char token-shape; or
`DefaultSanitizer(enableContentBasedDetection: false)` plus an explicit
deny-list/regex for the real secrets you just un-protected.

Extend rather than replace: `DefaultSanitizer(matcher:
SensitiveFieldMatcher(extraKeys: {'session_key', 'otp'}), fieldMask:
MaskingStrategy(keepStart: 2, keepEnd: 2))`.
`RegexValueSanitizer({RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'): '<email>'})` for
aggressive global rewrites.

## Verify (never ship a privacy change unverified)

1. Build a representative event and print the final payload:

```dart
final e = await BugReportClient.instance.createEvent(
  UnexpectedException(devMessage: 'privacy check'),
  additionalContext: {'probe': {'email': 'a@b.com', 'authToken': 'abcdefghijklmnopqrstuvwxyz123456', 'orderId': '1234567890123456'}},
);
debugPrint(const JsonEncoder.withIndent('  ').convert(e.toMap()));
```

2. Assert: planted secrets masked; denied paths ABSENT (not masked - absent);
   `exception.devMessage` still readable; payload under the size budget.
3. Check nothing you rely on for triage got masked by the content heuristics.
4. Remove the probe code. For a durable guarantee, move the probe into a unit
   test that runs the app's real sanitizer list over a fixture map and asserts
   on the output.

## Common mistakes

- Putting `SizeBudgetSanitizer` first (measures pre-mask sizes, then masking
  changes them) or omitting it (unbounded payloads).
- Deny-listing `context.user.email` but forgetting breadcrumb data or
  `additionalContext` carrying the same value under another key - content
  heuristics do not catch emails (only key matching does; the key must be/contain
  `email`). Add a RegexValueSanitizer for emails when this must be airtight.
- Assuming `isSensitiveField`/`sensitiveFields` from `helpers.dart` drive the
  DefaultSanitizer - they are a separate public utility; the sanitizer has its
  own internal key set. Extending one does not extend the other.
- Expecting sanitizers to protect what a custom Reporter reads from
  `event.context` directly - sanitization only covers `event.toMap()`; fix the
  reporter (see extend-pipeline skill).

## Scenario

"Compliance says device identifiers and wifi info must never be reported" ->
add/extend `FilterSanitizer(DenyListFilter({...device paths above...,
'context.network.wifi'}))` as the FIRST sanitizer, keep the rest of the chain,
run the verification probe, and add the fixture-based unit test asserting those
paths are absent from the final payload.
