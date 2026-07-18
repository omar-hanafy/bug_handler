# CHANGELOG

## 1.0.0-dev.6

- **Added** installable AI coding-assistant support for Claude Code and OpenAI Codex, distributed from the GitHub repository (not the pub.dev archive): `/plugin marketplace add omar-hanafy/bug_handler` (Claude Code) or `codex plugin marketplace add omar-hanafy/bug_handler` (Codex CLI), then install the `bug-handler` plugin. One shared plugin ships seven package-specific skills - `setup-reporting`, `guard-workflow`, `extend-pipeline`, `tune-privacy`, `diagnose-reporting`, `migrate-legacy-api` (0.0.1-dev.x -> 1.0.0-dev.x), and `audit-error-handling` - backed by verified API/behavior references, production integration patterns, and migration fixtures.
- **Added** "AI coding-assistant support" section in the README and detailed plugin documentation in `doc/ai-plugin.md`; repository-level maintainer guidance (`AGENTS.md`), plugin integrity validation (`dart tool/validate_plugin.dart`), and CI.
- **No runtime changes**: the Dart/Flutter package API and behavior are identical to 1.0.0-dev.5. The plugin tree is excluded from the pub.dev archive via `.pubignore`.

## 1.0.0-dev.5

- **Added** `BugReportClient.captureSafely()`: the single never-throw reporting entry point. It is a no-op before `initialize()` and swallows any failure in context collection, sanitization, or delivery, so reporting can never crash the host app.
- **Fixed** `guard()`/`guardSync()` reporting path: no longer throws when the client is uninitialized or delivery fails; `Err` is still returned to callers either way.
- **Fixed** `ErrorBoundary` reporting: a delivery failure no longer throws into microtasks, stream `onError` handlers (where it also swallowed the stream's error), or the "Report" button.
- **Fixed** `BugReportBindings`: uncaught framework/zone/isolate errors are now reported with `handled: false`. Previously they were marked `handled: true`, which mislabeled events and made `Policy(reportHandled: false)` drop every uncaught error.
- **Fixed** default `ErrorBoundary` fallback: the "Report" button uses `ScaffoldMessenger.maybeOf`, so it no longer crashes when the boundary sits above `MaterialApp`.
- **Added** first test suite locking the never-throw invariant (uninitialized client, throwing reporter, failing outbox).

## 1.0.0-dev.4
updated all deps

## 1.0.0-dev.3
used dart_helper_utils: ^6.0.0

## 1.0.0-dev.2
- Updated debs

## 1.0.0-dev.1

- Prepare for publishing: filled out pubspec metadata (links, description, supported platforms).
- Added Flutter example app showcasing context providers, guards, and reporters.
- Fixed analyzer warnings and enforced dependency version constraints.

## 1.0.0

- **INITIAL**: Initial release.
