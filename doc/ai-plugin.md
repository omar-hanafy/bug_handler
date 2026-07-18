# bug_handler AI coding-assistant plugin

Installable, package-specific support for AI coding agents working with the
[`bug_handler`](https://pub.dev/packages/bug_handler) Flutter error-reporting
toolkit. One plugin, two ecosystems: **Claude Code** and **OpenAI Codex** read
their own manifests from the same plugin tree; the skills are shared
[agentskills.io](https://agentskills.io)-standard `SKILL.md` files.

This is developer tooling, not a runtime feature of the Dart package. The
plugin is distributed from this Git repository only; the pub.dev archive
deliberately excludes it (pub strips hidden directories, which would break the
manifests).

## What it does

The plugin teaches agents this package's actual contracts - verified against
the source, the test suite, and two production integrations - instead of
leaving them to guess from the README. That includes the things agents
reliably get wrong on their own: the extra imports (`flutter/bindings.dart`,
`flutter/error_boundary.dart`, `helpers.dart` are not exported by the main
entrypoint), the exact policy-gate order, dedupe-by-exception-type, the fact
that `isReportable` is not enforced by the pipeline, reporter return-value
semantics (`true` for intentional skips), and the empty Sentry/Crashlytics
adapter placeholders.

## Installation

Claude Code:

```
/plugin marketplace add omar-hanafy/bug_handler
/plugin install bug-handler@bug-handler
```

Non-interactive: `claude plugin marketplace add omar-hanafy/bug_handler` and
`claude plugin install bug-handler@bug-handler`.

OpenAI Codex (CLI v0.131.0+):

```
codex plugin marketplace add omar-hanafy/bug_handler
codex plugin add bug-handler@bug-handler
```

Then **start a new session** (Codex requires it; Claude Code picks the plugin
up after `/reload-plugins` or a restart).

Supported surfaces: all Claude Code surfaces with plugin support; Codex CLI and
ChatGPT Work mode. Codex plugins are currently **not** available in the IDE
extension, Chat mode, or mobile - do not expect the skills there.

## Skills

| Skill | When it activates | Try |
|---|---|---|
| `setup-reporting` | First-time integration, bootstrap wiring, ClientConfig/Policy/reporter choices | "Add bug_handler crash reporting to this app" |
| `guard-workflow` | Feature work in a bug_handler app: repositories, cubits/notifiers, error states, try/catch refactors | "Add a favorites repository and cubit with proper error handling" |
| `extend-pipeline` | Custom reporters (Sentry/Crashlytics/HTTP), custom context providers, transforms | "Send our reports to Crashlytics" |
| `tune-privacy` | Sanitizer/filter configuration, masking surprises, PII compliance, payload budgets | "Order IDs arrive masked as ****1234 - fix that" |
| `diagnose-reporting` | Missing/duplicate/unexpected reports, outbox buildup, silent drops | "Errors stopped arriving in Sentry since last release" |
| `migrate-legacy-api` | Projects on 0.0.1-dev.x or containing `BugReporter`/`ErrorHandler`/`wrapper` | "Migrate this app off the old BugReporter API" |
| `audit-error-handling` | Reviews: PR review, "are we using bug_handler correctly", pre-release audits | "Review this PR's error handling" |

Explicit invocation: Claude Code `/bug-handler:<skill-name>`; Codex
`$<skill-name>` mention or browse with `/skills`.

Supporting material inside the plugin, loaded by skills on demand:
`references/api-quick-reference.md` (exact signatures + import map),
`references/exceptions-catalog.md` (all 13+ exception types with defaults),
`references/policy-and-delivery.md` (gate order, outbox truth table,
never-throw matrix), `references/production-patterns.md` (Sentry-transport
reporter, manual-zone bootstrap, state-management recipes),
`references/legacy-api-mapping.md` (complete 0.0.1-dev.x -> 1.0.0-dev.x
translation), and `fixtures/migration/` (before/after example project files).

## Permissions and trust

The plugin contains **only** instruction markdown, reference documents, and
illustrative fixture code. No hooks, no MCP servers, no executables, no network
access, no telemetry. Skills operate through your agent's ordinary tools
(reading/editing project files, running `dart`/`flutter` commands) under your
agent's normal permission model.

## Compatibility

- Package: skills target bug_handler **>= 1.0.0-dev.5** and understand the
  older 1.0.0-dev.1..4 releases (notably: `captureSafely` and the never-throw
  guard path exist only since dev.5) plus the legacy 0.0.1-dev.x line for
  migration purposes.
- Clients: Claude Code >= 2.1.196 recommended (marketplace validation
  improvements); Codex CLI >= 0.131.0 (`codex plugin` commands; the plugin
  system itself needs >= 0.110.0).
- The plugin version always matches the package version it was released with.

## Updating and removing

Claude Code: `/plugin marketplace update bug-handler` to refresh, then update
the plugin from the `/plugin` UI; uninstall via `/plugin` or
`claude plugin uninstall bug-handler@bug-handler`.

Codex: `codex plugin marketplace upgrade bug-handler`, remove with
`codex plugin remove bug-handler@bug-handler`.

## Troubleshooting

- **Skills do not appear**: start a new session (Codex always needs one after
  install; Claude Code needs `/reload-plugins` or a restart). In Claude Code,
  `claude plugin list` shows installed plugins; in Codex, `codex plugin list`.
- **Codex IDE extension**: plugins are not supported there yet - use the CLI or
  ChatGPT Work mode.
- **Marketplace add fails**: both catalogs live at the repository root
  (`.claude-plugin/marketplace.json` for Claude Code,
  `.agents/plugins/marketplace.json` for Codex); adding by `omar-hanafy/bug_handler`
  requires plain Git access to github.com.
- **A skill gives stale advice after a package release**: update the
  marketplace (commands above) so the cached plugin matches the package version
  in your pubspec.

## For maintainers

Local validation before any release or plugin change:

```
dart tool/validate_plugin.dart       # manifests, version sync, frontmatter, refs
claude plugin validate . --strict    # marketplace (when Claude Code installed)
claude plugin validate plugins/bug-handler --strict
claude --plugin-dir plugins/bug-handler   # live local smoke test
```

Rules (also in AGENTS.md): the version in `pubspec.yaml`, both `plugin.json`
manifests, and the Claude marketplace entries must match; package API changes
update `references/` and affected skills in the same change; every future
breaking package release ships a dedicated `migrate-<from>-to-<to>` skill
modeled on `migrate-legacy-api`; behavioral scenarios live in
`plugins/bug-handler/evals/scenarios.md` and the ones touching changed
behavior are re-run before release.
