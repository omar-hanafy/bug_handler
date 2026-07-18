# bug_handler maintainer guide

Flutter error-reporting package published to pub.dev. This file is for agents
working on THIS repository. Guidance for using the package inside consumer apps
lives in the installable plugin under `plugins/bug-handler/` - do not duplicate
it here.

## Validation commands (run before claiming any change done)

- `dart format .` (repo root; also fixes trailing newlines)
- `dart analyze` - must be clean; `public_member_api_docs` is an ERROR here, so
  every new public member needs a `///` doc comment.
- `flutter test` - full suite.
- `dart tool/validate_plugin.dart` - after ANY change under `plugins/`,
  `.claude-plugin/`, `.agents/`, or a version bump.
- `dart pub publish --dry-run` - before release; inspect the file list: the
  `plugins/` tree, `.claude-plugin/`, `.agents/`, and marketplace files must NOT
  appear in the archive (`.pubignore` governs this).

## Invariants

- Reporting must never crash the host app. `captureSafely`, `guard`,
  `guardSync`, `BugReportBindings`, and `ErrorBoundary` swallow reporting-path
  failures; `test/never_throw_invariant_test.dart` locks this. Any change to
  `lib/core/client.dart`, `lib/core/guard.dart`, or `lib/flutter/*` must keep
  those tests passing unmodified.
- `BaseException.isReportable` is intentionally NOT enforced by the pipeline in
  1.0.0-dev.x. Enforcing it is a behavior-breaking change: it needs a changelog
  warning, plugin-skill updates, and a migration note - do not "fix" it casually.
- `lib/reporters/adapters/{sentry,crashlytics}.dart` are intentionally empty
  placeholder files (not exported). Leave them empty or implement them fully
  with tests; no half-stubs.
- The `legacy_version` branch is the published 0.0.1-dev.x line (old API,
  republished below 1.0.0 on purpose). Never merge it into `main`; legacy-only
  fixes are committed and published from that branch.

## Versioning and release

- Version lives in five places and must be identical: `pubspec.yaml`,
  `plugins/bug-handler/.claude-plugin/plugin.json`,
  `plugins/bug-handler/.codex-plugin/plugin.json`, and the version fields in
  `.claude-plugin/marketplace.json`. `dart tool/validate_plugin.dart` fails on
  drift.
- Current convention: prereleases `1.0.0-dev.N`, release commit message is the
  bare version (e.g. `1.0.0-dev.6`), tag `v<version>`, then `dart pub publish`.
- Update `CHANGELOG.md` for every published version.

## Agent plugin (plugins/bug-handler/)

- One canonical tree serves Claude Code and Codex; skills are shared
  agentskills.io SKILL.md files, manifests differ per platform. Keep skill
  frontmatter to `name` + `description` (folded `>-` blocks - plain scalars
  break on `:` and quotes).
- When changing package behavior or public API, update the affected
  `plugins/bug-handler/references/*.md` and skills in the same change.
- Every future breaking release must ship a dedicated
  `migrate-<from>-to-<to>` skill modeled on `migrate-legacy-api`, plus an entry
  in the legacy mapping reference if the old line is still supported.
- Fixture code under `plugins/bug-handler/fixtures/` is illustrative and
  excluded from analysis (`analysis_options.yaml` excludes `plugins/**`); do
  not "fix" analyzer findings there by deleting the legacy API usage - it is
  the point of the fixture.
