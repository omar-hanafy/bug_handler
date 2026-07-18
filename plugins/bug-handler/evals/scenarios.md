# Behavioral evaluation scenarios

Manual/agent-run scenarios for the plugin's skills. Run with the plugin loaded
(`claude --plugin-dir plugins/bug-handler` or a Codex session with the plugin
installed) against a scratch Flutter project unless stated. Each skill has:
positive trigger, execution, negative (must NOT over-trigger), and missing-info
cases. Record pass/fail per run in the release notes when validating a release.

Legend: [T] should trigger/skill selected, [N] must not trigger, [E] execution
quality, [M] missing-information handling.

## setup-reporting

- [T] "Add bug_handler to this app and wire up crash reporting." Expect: version
  check, bootstrap-style decision based on existing main.dart, config built.
- [E] Project with existing runZonedGuarded + Sentry init: expect manual wiring
  (no runAppWithReporting), OnErrorIntegration guidance, flush() after runApp,
  no double wiring.
- [N] "Set up Firebase Crashlytics in this app" in a project with NO bug_handler
  dependency and no mention of it: generic Crashlytics setup, this skill silent.
- [M] Project resolves bug_handler 0.0.1-dev.4: expect redirect to
  migrate-legacy-api, no current-API wiring emitted.

## guard-workflow

- [T] "Add a favorites repository and cubit with proper error handling."
- [E] Expect: repository rethrows BaseException subclass, guard with
  'ClassName.method' source, BaseException stored in state (not String), UI on
  userMessage; analyze/test steps run.
- [N] "Handle errors in this bash deploy script": silent.
- [M] App stores String errors in its shared state container: expect the skill
  to follow sibling convention AND surface the limitation, not silently churn
  the shared container.

## extend-pipeline

- [T] "Send bug_handler reports to Crashlytics."
- [E] Expect: reporter reads event.toMap() (never event.context), returns true
  on intentional skip, false only on delivery failure; unit test of the
  contract; warning that shipped adapters are empty.
- [N] "Add a Dio interceptor for auth headers": silent.
- [M] "Send reports to our backend" with no endpoint specified: asks for the
  endpoint/auth rather than inventing one.

## tune-privacy

- [T] "Order IDs show up masked as ****1234 in our reports, fix that."
- [E] Expect: identifies the 13-19-digit card heuristic, proposes key rename or
  enableContentBasedDetection:false + explicit rules, runs/describes the
  verification probe, keeps DefaultSanitizer in the chain.
- [N] "Mask the API key in our README": silent.
- [M] "Make reports GDPR-safe" with no data inventory: asks what fields exist /
  runs the probe first instead of guessing.

## diagnose-reporting

- [T] "Errors stopped arriving in Sentry since last release."
- [E] Expect: elimination in gate order (init -> capture path -> env -> severity
  -> handled -> sampling -> dedupe-by-type -> rate limit -> delivery -> outbox),
  diagnosis reported before fixes.
- [N] "Flutter build fails with a Gradle error": silent.
- [M] No reproduction available: expect the probe snippet offered, not blind
  config edits.

## migrate-legacy-api

- [T] "This app still uses BugReporter and wrapper(), migrate it."
- [E] On fixtures/migration/legacy_before: output matches current_after in API
  usage; didReport branches flagged as judgment; isReportable behavior change
  called out; sentry_flutter added as explicit dep.
- [N] Project already on 1.0.0-dev.6 with zero legacy symbols: reports
  "already migrated", changes nothing.
- [M] Project on an unknown fork version: states the path is unsupported and
  proceeds symbol-by-symbol only with consent.
- Edge: project where only half the files were migrated earlier: uses the
  inventory greps as worklist, converges to zero legacy symbols.

## audit-error-handling

- [T] "Review this PR's error handling" (diff adds a repository + cubit).
- [E] Findings carry file:line, severity ranking, clean categories listed;
  respects app wrapper conventions; does not rewrite code unasked.
- [N] "Audit our app's accessibility": silent.
- [M] Asked to audit with no diff and a huge repo: scopes explicitly (asks or
  states chosen scope) rather than skimming everything shallowly.

## Cross-cutting

- Namespacing: Claude lists skills as bug-handler:<name>; `/bug-handler:diagnose-reporting`
  invokes directly. Codex `$<name>` mention works after a new session.
- References resolve: each skill's ../../references/*.md paths exist in the
  installed cache (Claude: ~/.claude/plugins/cache/...; Codex:
  ~/.codex/plugins/cache/...).
- No skill triggers on adjacent-but-unrelated Flutter work (state management
  refactors with no error-handling ask, pure UI work).
